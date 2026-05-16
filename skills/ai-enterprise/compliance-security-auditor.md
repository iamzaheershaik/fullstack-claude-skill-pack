---
name: Compliance & Security Code Auditor
category: ai-enterprise
version: 1.0.0
description: >
  Scan code for license compliance, security vulnerabilities, and regulatory violations. Combines SAST, SCA, and LLM reasoning. Integrates into CI/CD. Node.js/TypeScript.
author: Zaheer Shaik
tags:
  - security
  - compliance
  - auditing
  - ai
  - enterprise
---

# Compliance & Security Code Auditor — Claude Skill (AI Enterprise)

> Scan code for license compliance, security vulnerabilities, and regulatory violations. Combines SAST, SCA, and LLM reasoning. Integrates into CI/CD. Node.js/TypeScript.

---

## Core Directives

1. **Shift left.** Catch compliance and security issues in PR, not in production.
2. **Explain, don't just flag.** Every finding includes severity, impact, and remediation steps.
3. **Zero false-negative tolerance on critical.** Miss nothing on OWASP Top 10. Tolerate some false positives.
4. **Audit trail everything.** Every scan, finding, and decision is logged for regulatory proof.

---

## 1 · License Scanner

### Dependency License Detector
```typescript
import { execSync } from 'child_process';

interface LicenseResult {
  package: string;
  version: string;
  license: string;
  risk: 'safe' | 'caution' | 'restricted' | 'unknown';
  action: string;
}

const RESTRICTED = ['GPL-2.0', 'GPL-3.0', 'AGPL-3.0', 'SSPL-1.0', 'EUPL-1.1'];
const CAUTION = ['LGPL-2.1', 'LGPL-3.0', 'MPL-2.0', 'EPL-1.0', 'CDDL-1.0'];
const SAFE = ['MIT', 'Apache-2.0', 'BSD-2-Clause', 'BSD-3-Clause', 'ISC', 'CC0-1.0', '0BSD', 'Unlicense'];

export function scanDependencyLicenses(projectDir: string): LicenseResult[] {
  const output = execSync('npx license-checker --json --production', {
    cwd: projectDir, encoding: 'utf-8', timeout: 30000,
  });

  const deps = JSON.parse(output);
  const results: LicenseResult[] = [];

  for (const [pkg, info] of Object.entries(deps) as [string, any][]) {
    const license = info.licenses || 'UNKNOWN';
    let risk: LicenseResult['risk'] = 'unknown';
    let action = 'Review manually';

    if (SAFE.some(l => license.includes(l))) { risk = 'safe'; action = 'No action needed'; }
    else if (RESTRICTED.some(l => license.includes(l))) { risk = 'restricted'; action = 'REMOVE or replace — copyleft incompatible with proprietary code'; }
    else if (CAUTION.some(l => license.includes(l))) { risk = 'caution'; action = 'Review usage — dynamic linking may be required'; }

    results.push({ package: pkg, version: info.version || '', license, risk, action });
  }

  return results;
}
```

### Code Snippet License Detection
```typescript
import OpenAI from 'openai';
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

export async function detectCodeProvenance(code: string): Promise<{
  likelySource: string;
  licenseRisk: 'none' | 'low' | 'medium' | 'high';
  reasoning: string;
}> {
  const response = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages: [
      {
        role: 'system',
        content: `Analyze this code snippet for potential license/copyright issues.
Check for: known library patterns, copied Stack Overflow code, AI-generated patterns.
Return JSON: { "likelySource": string, "licenseRisk": "none"|"low"|"medium"|"high", "reasoning": string }`,
      },
      { role: 'user', content: code },
    ],
    max_tokens: 500,
    temperature: 0,
    response_format: { type: 'json_object' },
  });

  return JSON.parse(response.choices[0].message.content || '{}');
}
```

---

## 2 · Security Vulnerability Scanner

### OWASP Top 10 Checks
```typescript
interface SecurityFinding {
  rule: string;
  severity: 'critical' | 'high' | 'medium' | 'low' | 'info';
  file: string;
  line: number;
  code: string;
  description: string;
  remediation: string;
  owasp: string;
}

export function staticSecurityScan(files: { path: string; content: string }[]): SecurityFinding[] {
  const findings: SecurityFinding[] = [];

  for (const file of files) {
    const lines = file.content.split('\n');
    lines.forEach((line, i) => {
      // A01: Broken Access Control
      if (/\.find\(\s*\{?\s*\}?\s*\)/.test(line) && !file.content.includes('req.user')) {
        findings.push({ rule: 'NO_AUTH_CHECK', severity: 'high', file: file.path, line: i + 1, code: line.trim(),
          description: 'Database query without user scope — may expose other users\' data', remediation: 'Add user/org filter: .find({ org: req.user.orgId })', owasp: 'A01:2021' });
      }

      // A02: Cryptographic Failures
      if (/md5|sha1/i.test(line) && /password|secret|token/i.test(line)) {
        findings.push({ rule: 'WEAK_HASH', severity: 'critical', file: file.path, line: i + 1, code: line.trim(),
          description: 'Weak hash algorithm used for sensitive data', remediation: 'Use bcrypt/argon2 for passwords, SHA-256+ for tokens', owasp: 'A02:2021' });
      }

      // A03: Injection
      if (/\$\{.*req\.(body|query|params)/.test(line) && /query|exec|eval/.test(line)) {
        findings.push({ rule: 'INJECTION', severity: 'critical', file: file.path, line: i + 1, code: line.trim(),
          description: 'User input interpolated into query/command', remediation: 'Use parameterized queries or input validation', owasp: 'A03:2021' });
      }

      // A05: Security Misconfiguration
      if (/cors\(\s*\)/.test(line)) {
        findings.push({ rule: 'CORS_WILDCARD', severity: 'medium', file: file.path, line: i + 1, code: line.trim(),
          description: 'CORS configured with wildcard origin', remediation: 'Specify explicit origin whitelist', owasp: 'A05:2021' });
      }

      // A07: Auth Failures
      if (/jwt\.sign.*expiresIn.*['"](\d+d|30d|365d|never)['"]/i.test(line)) {
        findings.push({ rule: 'LONG_TOKEN', severity: 'medium', file: file.path, line: i + 1, code: line.trim(),
          description: 'JWT with very long expiration', remediation: 'Use 15m access + 7d refresh token pattern', owasp: 'A07:2021' });
      }

      // A09: Logging Failures
      if (/console\.(log|error).*password|secret|token|apiKey/i.test(line)) {
        findings.push({ rule: 'SECRET_LOG', severity: 'high', file: file.path, line: i + 1, code: line.trim(),
          description: 'Potential secret logged to console', remediation: 'Use structured logger with redaction', owasp: 'A09:2021' });
      }
    });
  }

  return findings;
}
```

### LLM-Powered Deep Analysis
```typescript
export async function deepSecurityAudit(code: string, filePath: string): Promise<SecurityFinding[]> {
  const response = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages: [
      {
        role: 'system',
        content: `You are a senior application security engineer. Perform a deep security audit.
Focus on: injection, auth bypass, IDOR, SSRF, race conditions, timing attacks, business logic flaws.
Return JSON array: [{ "rule": string, "severity": "critical"|"high"|"medium"|"low", "line": number, "description": string, "remediation": string, "owasp": string }]
Only report real issues — no theoretical or extremely unlikely attacks.`,
      },
      { role: 'user', content: `File: ${filePath}\n\`\`\`\n${code}\n\`\`\`` },
    ],
    max_tokens: 2000,
    temperature: 0,
    response_format: { type: 'json_object' },
  });

  const parsed = JSON.parse(response.choices[0].message.content || '{"findings":[]}');
  return (parsed.findings || []).map((f: any) => ({ ...f, file: filePath, code: '' }));
}
```

---

## 3 · SBOM Generation

### Software Bill of Materials
```typescript
interface SBOMEntry {
  name: string;
  version: string;
  license: string;
  supplier: string;
  checksum: string;
  dependencies: string[];
}

export function generateSBOM(projectDir: string): { spdxVersion: string; packages: SBOMEntry[] } {
  const pkgJson = JSON.parse(execSync('cat package.json', { cwd: projectDir, encoding: 'utf-8' }));
  const lockfile = JSON.parse(execSync('cat package-lock.json', { cwd: projectDir, encoding: 'utf-8' }));

  const packages: SBOMEntry[] = [];
  for (const [name, info] of Object.entries(lockfile.packages || {}) as [string, any][]) {
    if (!name || name === '') continue;
    packages.push({
      name: name.replace('node_modules/', ''),
      version: info.version || '',
      license: info.license || 'UNKNOWN',
      supplier: '',
      checksum: info.integrity || '',
      dependencies: Object.keys(info.dependencies || {}),
    });
  }

  return { spdxVersion: 'SPDX-2.3', packages };
}
```

---

## 4 · CI Integration

### GitHub Actions Workflow
```yaml
name: Compliance & Security Audit
on:
  pull_request:
    types: [opened, synchronize]
  schedule:
    - cron: '0 3 * * 1' # Weekly Monday 3 AM

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20, cache: npm }
      - run: npm ci
      - run: npx compliance-auditor scan --format=sarif --output=results.sarif
      - uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: results.sarif
      - run: npx compliance-auditor license-check --fail-on=restricted
      - run: npx compliance-auditor sbom --output=sbom.json
      - uses: actions/upload-artifact@v4
        with:
          name: compliance-report
          path: |
            results.sarif
            sbom.json
```

---

## 5 · Severity & Response Matrix

| Severity | Response Time | Action | Block PR? |
|---|---|---|---|
| Critical | Immediate | Fix required before merge | Yes |
| High | 24 hours | Fix required, temporary bypass with approval | Yes |
| Medium | 1 week | Track in issue, fix in next sprint | No (warn) |
| Low | Backlog | Document, fix when convenient | No |
| Info | None | Informational only | No |

### License Risk Matrix
| License | Risk | Commercial Use | Copyleft | Action |
|---|---|---|---|---|
| MIT, BSD, ISC | Safe | ✓ | ✗ | None |
| Apache-2.0 | Safe | ✓ | ✗ | Include NOTICE |
| LGPL | Caution | ✓ (dynamic link) | Partial | Review linking |
| GPL-2.0/3.0 | Restricted | ✗ (if proprietary) | ✓ | Replace |
| AGPL-3.0 | Restricted | ✗ (SaaS) | ✓ | Replace |
| SSPL | Restricted | ✗ | ✓ | Replace |
| UNKNOWN | Unknown | ? | ? | Investigate |

---

## 6 · Compliance Auditor Checklist

```
License:
✓ Dependency license scanning (production + dev)
✓ Copyleft detection (GPL, AGPL, SSPL)
✓ Code snippet provenance analysis (LLM-powered)
✓ SBOM generation (SPDX format)
✓ Attribution file generation (NOTICE/THIRD-PARTY)

Security:
✓ OWASP Top 10 static checks
✓ LLM deep audit for logic flaws
✓ Secret detection (API keys, passwords in code)
✓ Dependency vulnerability scanning (npm audit)
✓ SARIF output for GitHub Code Scanning

Compliance:
✓ Audit trail for every scan and finding
✓ Policy-as-code (configurable rules)
✓ Exemption management (approved waivers)
✓ Trend tracking (findings over time)

Integration:
✓ PR checks (block on critical/high)
✓ Scheduled weekly scans
✓ SARIF upload to GitHub Security tab
✓ Artifact upload (reports, SBOM)
```

---

## Response Format

```
1. Findings summary (critical/high/medium/low counts)
2. Detailed findings with file:line, description, remediation
3. License compliance status (safe/caution/restricted)
4. SBOM snapshot
```

**Never output:** auto-fixes for security issues (suggest only), findings without remediation steps.
**Always output:** severity level, OWASP category, remediation guidance, audit trail entry.

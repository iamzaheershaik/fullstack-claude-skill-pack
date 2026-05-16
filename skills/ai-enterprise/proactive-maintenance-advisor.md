---
name: Proactive Code Maintenance & Refactoring Advisor
category: ai-enterprise
version: 1.0.0
description: >
  Monitor code changes via Git hooks and CI, analyze for tech debt, dead code, and performance issues, and proactively suggest refactorings. Runs per-PR or on schedule. Node.js/TypeScript.
author: Zaheer Shaik
tags:
  - maintenance
  - refactoring
  - tech-debt
  - ai
  - enterprise
---

# Proactive Code Maintenance & Refactoring Advisor — Claude Skill (AI Enterprise)

> Monitor code changes via Git hooks and CI, analyze for tech debt, dead code, and performance issues, and proactively suggest refactorings. Runs per-PR or on schedule. Node.js/TypeScript.

---

## Core Directives

1. **Be proactive, not reactive.** Surface issues before developers ask — run on every PR and nightly.
2. **Signal, don't noise.** Rank suggestions by impact. Never flood PRs with trivial style nits.
3. **Explain the why.** Every suggestion includes business impact (perf, maintainability, bug risk).
4. **Respect developer flow.** Suggestions are comments, not blockers. Auto-fix only with explicit opt-in.

---

## 1 · Git Hook & CI Integration

### PR Webhook Handler
```typescript
import express from 'express';
import crypto from 'crypto';

const app = express();
app.use(express.json());

app.post('/webhook/github', async (req, res) => {
  // Verify signature
  const sig = req.headers['x-hub-signature-256'] as string;
  const hmac = crypto.createHmac('sha256', process.env.GITHUB_WEBHOOK_SECRET!);
  hmac.update(JSON.stringify(req.body));
  const expected = `sha256=${hmac.digest('hex')}`;
  if (sig !== expected) return res.status(401).send('Invalid signature');

  const { action, pull_request } = req.body;
  if (action === 'opened' || action === 'synchronize') {
    await analyzePR(pull_request.number, pull_request.head.sha, pull_request.base.sha);
  }
  res.status(200).send('OK');
});

async function analyzePR(prNumber: number, headSha: string, baseSha: string) {
  const diff = await fetchDiff(prNumber);
  const analysis = await runAnalysis(diff);
  await postComments(prNumber, analysis);
}
```

### GitHub Actions Integration
```yaml
# .github/workflows/maintenance-advisor.yml
name: Code Maintenance Advisor
on:
  pull_request:
    types: [opened, synchronize]
  schedule:
    - cron: '0 2 * * 1' # Weekly Monday 2 AM

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: npx maintenance-advisor analyze --pr=${{ github.event.pull_request.number }}
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
```

---

## 2 · Analysis Modules

### Tech Debt Scorer
```typescript
interface DebtScore {
  file: string;
  score: number; // 0-100, higher = more debt
  issues: { type: string; severity: 'low' | 'medium' | 'high'; message: string; line?: number }[];
}

export function analyzeFileDebt(filePath: string, content: string): DebtScore {
  const lines = content.split('\n');
  const issues: DebtScore['issues'] = [];

  // Complexity
  const cyclomaticComplexity = countComplexity(content);
  if (cyclomaticComplexity > 15) {
    issues.push({ type: 'complexity', severity: 'high', message: `Cyclomatic complexity: ${cyclomaticComplexity} (threshold: 15)` });
  }

  // File length
  if (lines.length > 300) {
    issues.push({ type: 'size', severity: 'medium', message: `File is ${lines.length} lines (threshold: 300)` });
  }

  // Long functions
  const longFunctions = findLongFunctions(content, 40);
  for (const fn of longFunctions) {
    issues.push({ type: 'function-length', severity: 'medium', message: `Function "${fn.name}" is ${fn.lines} lines`, line: fn.startLine });
  }

  // TODO/FIXME/HACK
  lines.forEach((line, i) => {
    if (/\b(TODO|FIXME|HACK|XXX)\b/.test(line)) {
      issues.push({ type: 'todo', severity: 'low', message: line.trim(), line: i + 1 });
    }
  });

  // Duplicated code (simple token matching)
  const duplicates = findDuplicateBlocks(content, 6);
  for (const dup of duplicates) {
    issues.push({ type: 'duplication', severity: 'medium', message: `Duplicate block (${dup.lines} lines) at lines ${dup.locations.join(', ')}` });
  }

  const score = Math.min(100, issues.reduce((s, i) => s + (i.severity === 'high' ? 25 : i.severity === 'medium' ? 10 : 3), 0));
  return { file: filePath, score, issues };
}

function countComplexity(code: string): number {
  const keywords = /\b(if|else if|for|while|switch|case|catch|\?\?|&&|\|\||\?)\b/g;
  return (code.match(keywords) || []).length + 1;
}

function findLongFunctions(code: string, threshold: number) {
  const fnRegex = /(?:function\s+(\w+)|(?:const|let)\s+(\w+)\s*=\s*(?:async\s*)?\()/g;
  const results: { name: string; lines: number; startLine: number }[] = [];
  let match;
  while ((match = fnRegex.exec(code))) {
    const name = match[1] || match[2];
    const start = code.slice(0, match.index).split('\n').length;
    // Simplified: count lines until matching brace
    let braces = 0, end = match.index;
    for (let i = match.index; i < code.length; i++) {
      if (code[i] === '{') braces++;
      if (code[i] === '}') { braces--; if (braces === 0) { end = i; break; } }
    }
    const lines = code.slice(match.index, end).split('\n').length;
    if (lines > threshold) results.push({ name, lines, startLine: start });
  }
  return results;
}

function findDuplicateBlocks(code: string, minLines: number) {
  const lines = code.split('\n').map(l => l.trim()).filter(Boolean);
  const seen = new Map<string, number[]>();
  const results: { lines: number; locations: number[] }[] = [];

  for (let i = 0; i <= lines.length - minLines; i++) {
    const block = lines.slice(i, i + minLines).join('\n');
    if (!seen.has(block)) seen.set(block, []);
    seen.get(block)!.push(i + 1);
  }

  for (const [, locs] of seen) {
    if (locs.length > 1) results.push({ lines: minLines, locations: locs });
  }
  return results;
}
```

### Dead Code Detector
```typescript
export function detectDeadExports(
  allFiles: { path: string; content: string }[],
): { file: string; symbol: string; line: number }[] {
  const exports = new Map<string, { file: string; line: number }>();
  const imports = new Set<string>();

  for (const f of allFiles) {
    // Collect exports
    const exportRegex = /export\s+(?:const|function|class|type|interface)\s+(\w+)/g;
    let m;
    while ((m = exportRegex.exec(f.content))) {
      exports.set(`${f.path}::${m[1]}`, { file: f.path, line: f.content.slice(0, m.index).split('\n').length });
    }

    // Collect imports
    const importRegex = /import\s+\{([^}]+)\}\s+from/g;
    while ((m = importRegex.exec(f.content))) {
      m[1].split(',').map(s => s.trim()).filter(Boolean).forEach(s => imports.add(s));
    }
  }

  const dead: { file: string; symbol: string; line: number }[] = [];
  for (const [key, val] of exports) {
    const symbol = key.split('::')[1];
    if (!imports.has(symbol)) dead.push({ ...val, symbol });
  }
  return dead;
}
```

---

## 3 · LLM-Powered Suggestions

### Refactoring Advisor
```typescript
import OpenAI from 'openai';
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

export async function suggestRefactoring(diff: string, fileContext: string): Promise<{
  suggestions: { file: string; line: number; suggestion: string; priority: 'low' | 'medium' | 'high' }[];
}> {
  const response = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages: [
      {
        role: 'system',
        content: `You are a senior code reviewer. Analyze this PR diff and suggest refactorings.
Focus on: complexity reduction, naming clarity, error handling, performance, security.
Skip: style/formatting, trivial changes. Return JSON array of suggestions.
Each: { "file": string, "line": number, "suggestion": string, "priority": "low"|"medium"|"high" }`,
      },
      { role: 'user', content: `## Diff\n${diff}\n\n## File Context\n${fileContext}` },
    ],
    max_tokens: 2000,
    temperature: 0.2,
    response_format: { type: 'json_object' },
  });

  return JSON.parse(response.choices[0].message.content || '{"suggestions":[]}');
}
```

### PR Comment Poster
```typescript
export async function postComments(
  prNumber: number,
  analysis: { suggestions: { file: string; line: number; suggestion: string; priority: string }[] },
) {
  const { Octokit } = await import('@octokit/rest');
  const octokit = new Octokit({ auth: process.env.GITHUB_TOKEN });
  const [owner, repo] = (process.env.GITHUB_REPOSITORY || '').split('/');

  // Post summary comment
  const summary = `## 🔧 Maintenance Advisor\n\n` +
    `Found **${analysis.suggestions.length}** suggestions\n\n` +
    analysis.suggestions.map(s => `- **[${s.priority.toUpperCase()}]** \`${s.file}:${s.line}\` — ${s.suggestion}`).join('\n');

  await octokit.issues.createComment({ owner, repo, issue_number: prNumber, body: summary });
}
```

---

## 4 · Dashboard & Tracking

### Debt Trend Schema
```typescript
import { Schema, model } from 'mongoose';

const debtSnapshotSchema = new Schema({
  project: { type: String, required: true, index: true },
  timestamp: { type: Date, default: Date.now },
  totalScore: Number,
  fileScores: [{ file: String, score: Number }],
  issuesByType: { type: Map, of: Number },
  suggestionsGenerated: Number,
  suggestionsApplied: Number,
});

export const DebtSnapshot = model('DebtSnapshot', debtSnapshotSchema);
```

### Severity Thresholds
| Metric | Green | Yellow | Red |
|---|---|---|---|
| File debt score | 0–20 | 21–50 | 51+ |
| Cyclomatic complexity | 1–10 | 11–20 | 21+ |
| File length (lines) | 1–200 | 201–400 | 401+ |
| Function length | 1–30 | 31–60 | 61+ |
| Duplicate blocks | 0 | 1–3 | 4+ |
| Dead exports | 0–5 | 6–15 | 16+ |

---

## 5 · Maintenance Advisor Checklist

```
Analysis:
✓ Cyclomatic complexity per function
✓ File and function length checks
✓ Dead export detection (unused exports)
✓ Duplicate code block detection
✓ TODO/FIXME/HACK tracking
✓ Dependency freshness (outdated packages)

Integration:
✓ GitHub PR webhook (auto-trigger on PR)
✓ GitHub Actions workflow (scheduled + PR)
✓ PR comment with prioritized suggestions
✓ Debt trend tracking over time

Quality:
✓ Rank suggestions by impact (high > medium > low)
✓ Never block PRs — suggestions only
✓ Allow developer feedback (dismiss / accept)
✓ Learn from accepted suggestions to improve

Security:
✗ Never auto-commit fixes without approval
✓ Respect .gitignore and private files
✓ Sanitize code before sending to LLM
```

---

## Response Format

```
1. Debt score summary (overall + per-file top offenders)
2. Prioritized suggestions with file:line references
3. Trend comparison (this PR vs baseline)
4. Auto-fixable items (with opt-in one-click apply)
```

**Never output:** style-only nits, trivial suggestions, blocking reviews.
**Always output:** severity level, business impact, file:line references, trend data.

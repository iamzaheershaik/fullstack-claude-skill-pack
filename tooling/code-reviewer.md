---
name: Code Reviewer
category: tooling
version: 1.0.0
description: >
  Systematic code review. Security scanning, performance checks, readability audit, PR review checklists, git hygiene, and ADR templates.
author: Zaheer Shaik
tags:
  - code-review
  - security
  - best-practices
  - git
  - tooling
---

# Code Reviewer — Claude Skill

> Systematic code review. Security scanning, performance checks, readability audit, PR review checklists, git hygiene, ADR templates.

---

## Core Directives

1. **Review the design, not just the code.** Does the approach solve the problem correctly?
2. **Security first.** Every review must check for auth bypass, injection, data leaks.
3. **Be specific.** "This could be better" → useless. "Extract this to a service because..." → useful.
4. **Praise what's good.** Positive reinforcement makes teams write better code.

---

## 1 · PR Review Checklist

### Quick Scan (30 seconds)
```
□ PR title describes what, not how
□ PR description explains WHY (not just what changed)
□ Changes are focused (single concern per PR)
□ PR size is reasonable (< 400 lines diff, split if larger)
□ No unrelated changes mixed in
□ Tests included for new behavior
□ No TODO comments left without tracking issue
```

### Security Review
```
□ No secrets/API keys committed (check .env, config files)
□ Auth middleware applied on protected routes
□ Input validation at API boundary (Zod/Joi schemas)
□ Parameterized queries (no string interpolation in queries)
□ No user-controlled data in SQL/NoSQL without sanitization
□ CORS configured with explicit origins (no wildcard in production)
□ Rate limiting on public/auth endpoints
□ Sensitive data excluded from logs (passwords, tokens, PII)
□ File uploads validated (MIME type, size, path traversal)
□ No eval(), innerHTML, or dangerouslySetInnerHTML without sanitization
```

### Performance Review
```
□ No N+1 queries (check loops with DB calls)
□ Database queries use appropriate indexes
□ SELECT only needed fields (no SELECT *)
□ Large lists paginated (not loading entire collections)
□ Images optimized and lazy-loaded
□ No synchronous operations blocking event loop
□ Appropriate caching strategy applied
□ Bundle impact considered for new dependencies
```

### Code Quality Review
```
□ Functions ≤ 30 lines, files ≤ 300 lines
□ No any types in TypeScript (use unknown + type guards)
□ Error handling present (not swallowing errors silently)
□ Early returns instead of deep nesting
□ Constants used instead of magic numbers/strings
□ Naming is descriptive (getUserById not getUsr)
□ No duplicated logic (DRY without over-abstracting)
□ Side effects isolated at boundaries
```

### Testing Review
```
□ Tests cover the main happy path
□ Tests cover key edge cases and error paths
□ Tests verify behavior, not implementation
□ No flaky tests (timing-dependent, order-dependent)
□ Mock at boundaries only (DB, external APIs)
□ Test names describe expected behavior
□ Coverage doesn't decrease significantly
```

---

## 2 · Common Code Smells

### Critical (Must Fix)
| Smell | Problem | Fix |
|---|---|---|
| SQL/NoSQL injection | User input in query strings | Parameterized queries, ORM |
| Missing auth check | Unauthorized access to protected resource | Add authenticate middleware |
| Hardcoded secret | Secret exposed in code/logs | Move to env vars |
| Unvalidated input | Injection, crashes, data corruption | Zod schema at API boundary |
| Swallowed error | Silent failures, hard to debug | Log + re-throw or handle |

### Warning (Should Fix)
| Smell | Problem | Fix |
|---|---|---|
| N+1 query | Performance degradation | populate() / batch load |
| God function (>50 lines) | Hard to test, hard to read | Extract into smaller functions |
| Deep nesting (>3 levels) | Hard to follow logic | Early returns, extract functions |
| Boolean parameter | Unclear at call site | Use options object or enum |
| Copy-paste code | Maintenance nightmare | Extract shared utility |

### Info (Consider Fixing)
| Smell | Problem | Fix |
|---|---|---|
| Magic number | Intent unclear | Named constant |
| Unused import | Dead code noise | Remove |
| Inconsistent naming | Cognitive load | Follow established conventions |
| Missing TypeScript type | Implicit any risks | Add explicit type |
| Comment explaining obvious code | Noise | Delete comment, rename if needed |

---

## 3 · Security Vulnerability Scanning

### npm audit
```bash
# Check for known vulnerabilities
npm audit

# Fix automatically (minor/patch updates)
npm audit fix

# See what would change
npm audit fix --dry-run

# Force fix (may include breaking changes)
npm audit fix --force
```

### Dependency Review
```bash
# Check for outdated packages
npm outdated

# Check for unused dependencies
npx depcheck

# Check bundle size impact
npx bundlephobia <package-name>
```

### CI Security Scan
```yaml
security:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - run: npm ci
    - run: npm audit --audit-level=high
    - name: Check for secrets
      uses: trufflesecurity/trufflehog@main
      with:
        path: ./
        base: ${{ github.event.repository.default_branch }}
```

### Secret Detection
```
Files to check for leaked secrets:
✓ .env files (should be in .gitignore)
✓ Config files (hardcoded URLs, keys)
✓ Docker files (build args with secrets)
✓ CI/CD files (inline secrets instead of GitHub Secrets)
✓ Test files (real API keys instead of mocks)
✓ README/docs (example configs with real values)
```

---

## 4 · Git Hygiene

### Commit Messages (Conventional Commits)
```
type(scope): description

feat(auth): add password reset flow
fix(api): handle null response from Stripe
docs(readme): add deployment instructions
refactor(posts): extract validation to middleware
test(auth): add integration tests for login
chore(deps): update mongoose to v8
perf(db): add compound index on posts.status+createdAt
```

### Types
| Type | When |
|---|---|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `test` | Adding or fixing tests |
| `chore` | Build process, dependency updates |
| `perf` | Performance improvement |
| `ci` | CI/CD changes |

### Branch Naming
```
feature/auth-password-reset
fix/login-redirect-loop
hotfix/stripe-webhook-500
docs/api-documentation
refactor/post-service-extraction
```

### PR Sizing Guidelines
| Size | Lines Changed | Review Time | Risk |
|---|---|---|---|
| XS | < 50 | 10 min | Low |
| S | 50-200 | 30 min | Low |
| M | 200-400 | 1 hour | Medium |
| L | 400-800 | 2+ hours | High |
| XL | 800+ | **Split this PR** | **Very High** |

---

## 5 · Review Communication

### Tone
```
✓ "Have you considered X? It would help with Y."
✓ "Nice approach! One suggestion: ..."
✓ "This needs to change because [security/correctness reason]."
✗ "Why would you do it this way?"
✗ "This is wrong."
✗ "Just use X instead." (no context)
```

### Comment Prefixes
```
[MUST]    — Blocking. Must fix before merge.
[SHOULD]  — Strong suggestion. Fix unless there's a good reason not to.
[NIT]     — Nitpick. Optional, stylistic preference.
[Q]       — Question. Seeking understanding, not necessarily requesting change.
[PRAISE]  — Acknowledging good work.
```

### Examples
```
[MUST] This query is vulnerable to injection. Use parameterized query:
`User.findOne({ email })` instead of `User.findOne({ email: req.body.email })`

[SHOULD] Consider extracting this validation logic into a middleware.
It's duplicated in 3 controllers.

[NIT] Minor: consistent naming — this uses `getData` but other services use `findAll`.

[Q] Is there a reason we're not using the existing `formatDate` util here?

[PRAISE] Clean separation of concerns here. The service layer is very testable.
```

---

## 6 · Architecture Decision Records (ADR)

### Template
```markdown
# ADR-001: Use MongoDB for Primary Database

## Status
Accepted

## Context
We need a database for our application. The data model is document-heavy
with flexible schemas that change frequently during development.

## Decision
Use MongoDB with Mongoose ODM.

## Consequences
**Positive:**
- Flexible schema during rapid development
- Native JSON storage matches our API responses
- Good horizontal scaling with sharding

**Negative:**
- No native joins (use populate or aggregation)
- Less data integrity enforcement than PostgreSQL
- Need to manage indexes manually

## Alternatives Considered
- PostgreSQL + Drizzle: Better for relational data but over-constraining for our flexible schema needs.
- DynamoDB: Lock-in to AWS, complex query patterns.
```

### When to Write ADRs
```
✓ Choosing a database, ORM, or major library
✓ Authentication strategy decision
✓ API design choices (REST vs GraphQL)
✓ Architecture changes (monolith → microservices)
✓ Infrastructure decisions (hosting, CI/CD platform)
✗ Don't ADR: syntax preferences, minor library choices, standard patterns
```

---

## 7 · Automated Review Tools

### ESLint Config
```json
{
  "extends": [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended",
    "plugin:import/recommended",
    "prettier"
  ],
  "rules": {
    "no-console": "warn",
    "@typescript-eslint/no-explicit-any": "error",
    "@typescript-eslint/no-unused-vars": ["error", { "argsIgnorePattern": "^_" }],
    "import/order": ["error", { "groups": ["builtin", "external", "internal"] }],
    "no-restricted-imports": ["error", { "patterns": ["../*"] }]
  }
}
```

### Pre-commit Hooks (Husky + lint-staged)
```json
// package.json
{
  "lint-staged": {
    "*.{ts,tsx}": ["eslint --fix", "prettier --write"],
    "*.{json,md,yml}": ["prettier --write"]
  }
}
```

```bash
npx husky init
echo "npx lint-staged" > .husky/pre-commit
```

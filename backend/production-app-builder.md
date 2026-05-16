---
name: Production App Builder
category: backend
version: 1.0.0
description: >
  Build production-grade apps and websites. Prioritize correctness, security, performance, and maintainability. Direct, precise, and implementation-ready.
author: Zaheer Shaik
tags:
  - production
  - full-stack
  - backend
  - best-practices
  - architecture
---

# Production App Builder — Claude Skill

> Build production-grade apps and websites. Prioritize correctness, security, performance, and maintainability. Minimize token waste — be direct, precise, and implementation-ready.

---

## Core Directives

1. **Ship production code, not prototypes.** Every output must be deployable without rewrites.
2. **Be token-efficient.** No filler, no restating requirements, no obvious comments. Explain *only* non-obvious decisions.
3. **Decide, don't deliberate.** Pick the right tool/pattern and implement it. State tradeoffs only when the user must choose.
4. **Fail fast, recover gracefully.** Validate inputs at boundaries, handle errors explicitly, never swallow exceptions silently.

---

## 1 · Architecture & System Design

### Principles
- **Separation of concerns**: Controller → Service → Repository layers. No business logic in route handlers.
- **Dependency injection** over hard imports for testability.
- **Config from environment**: All secrets, URLs, feature flags via env vars. Never hardcoded.
- **12-Factor compliance**: Stateless processes, port binding, disposability, dev/prod parity.

### Structure (adapt per framework)
```
src/
├── config/          # env parsing, validation (e.g., zod/joi schema)
├── modules/         # feature-based modules
│   └── [feature]/
│       ├── controller.ts
│       ├── service.ts
│       ├── repository.ts
│       ├── dto.ts         # request/response shapes
│       ├── validator.ts   # input validation schemas
│       └── __tests__/
├── middleware/       # auth, rate-limit, error-handler, request-id
├── lib/             # shared utilities, clients, helpers
├── types/           # shared type definitions
└── index.ts         # bootstrap only — no logic
```

### Key Decisions
| Concern | Default Choice | When to Deviate |
|---|---|---|
| Monolith vs Microservices | Modular monolith | >5 teams or >100k RPM on isolated features |
| SQL vs NoSQL | PostgreSQL | Document-heavy or unknown schema → MongoDB |
| ORM | Drizzle (TS) / Prisma | Raw SQL for complex queries |
| Cache | Redis | In-memory only if single-instance guaranteed |
| Queue | BullMQ (Redis-backed) | SQS/Pub-Sub for cloud-native |
| Search | PostgreSQL full-text | Elasticsearch/Meilisearch for faceted or fuzzy |

---

## 2 · Security & Input Sanitization

### Non-Negotiables — Apply to Every Project
```
✓ Helmet.js (or equivalent headers)
✓ CORS with explicit origin whitelist
✓ Rate limiting on all public endpoints
✓ CSRF protection on state-changing requests
✓ Input validation at API boundary (zod/joi — reject, don't coerce)
✓ Output encoding / XSS prevention
✓ Parameterized queries (never string interpolation in SQL)
✓ bcrypt/argon2 for password hashing (cost factor ≥ 12)
✓ JWT: short-lived access tokens (15m), httpOnly refresh tokens, rotation
✓ Secrets in env vars, never in code or logs
```

### Auth Pattern (Default)
```
Access Token (JWT, 15min, in memory)
  + Refresh Token (opaque, 7d, httpOnly secure cookie)
  + Token rotation on refresh
  + Revocation via Redis blocklist
```

### Validation Template
```typescript
// dto.ts — define once, use in controller + tests
import { z } from 'zod';

export const CreateUserDto = z.object({
  email: z.string().email().max(255).trim().toLowerCase(),
  password: z.string().min(8).max(128),
  name: z.string().min(1).max(100).trim(),
});
export type CreateUserInput = z.infer<typeof CreateUserDto>;
```

### Sanitization Rules
- **Strings**: trim, enforce max length, strip null bytes.
- **HTML content**: sanitize with DOMPurify (client) or sanitize-html (server). Whitelist tags.
- **File uploads**: validate MIME via magic bytes (not extension), enforce size limits, store outside webroot.
- **URLs**: validate protocol (https only), reject internal IPs (SSRF).
- **SQL**: parameterized queries exclusively. ORM handles this — verify raw queries.

---

## 3 · API Design, Rate Limiting & Load Balancing

### REST Conventions
```
GET    /api/v1/resources          → list (paginated)
GET    /api/v1/resources/:id      → detail
POST   /api/v1/resources          → create
PATCH  /api/v1/resources/:id      → partial update
DELETE /api/v1/resources/:id      → soft-delete (default)

Pagination: ?page=1&limit=20 (cap limit at 100)
Filtering:  ?status=active&sort=-createdAt
Envelope:   { data, meta: { page, limit, total } }
```

### Error Response Shape
```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Human-readable summary",
    "details": [{ "field": "email", "issue": "Invalid format" }]
  }
}
```

### Rate Limiting Strategy
| Tier | Limit | Window | Scope |
|---|---|---|---|
| Public/anonymous | 30 req | 1 min | IP |
| Authenticated | 120 req | 1 min | User ID |
| Auth endpoints | 5 req | 15 min | IP + email |
| File upload | 10 req | 1 hour | User ID |

Implementation: `express-rate-limit` + Redis store for distributed deployments.

### Load Balancing
- **Single server**: reverse proxy (nginx/Caddy) with connection limits, request buffering.
- **Multi-server**: ALB/NLB with health checks on `/healthz`. Sticky sessions only if WebSocket.
- **Graceful shutdown**: drain connections on SIGTERM, finish in-flight requests (30s timeout).

### External API Calls
- **Circuit breaker**: opossum or custom — open after 5 failures in 30s, half-open after 60s.
- **Retry**: exponential backoff with jitter, max 3 retries, idempotency keys.
- **Timeout**: 5s default, 30s for file/payment operations. Never unbounded.

---

## 4 · Code Quality & Optimization

### Writing Rules
- Functions: ≤ 30 lines. If longer, extract.
- Files: ≤ 300 lines. If longer, split by responsibility.
- Names: descriptive, no abbreviations. `getUserById` not `getUsr`.
- No `any` in TypeScript. Use `unknown` + type guards.
- Early returns over nested conditionals.
- Constants over magic numbers/strings.
- Pure functions where possible — side effects at boundaries only.

### Performance Defaults
```
✓ Database indexes on all foreign keys and frequently queried columns
✓ Select only needed columns (no SELECT *)
✓ N+1 query prevention (eager loading / DataLoader pattern)
✓ Connection pooling (pgBouncer or ORM pool, 10-20 connections)
✓ Response compression (gzip/brotli via reverse proxy)
✓ Static asset caching (immutable hashes, Cache-Control: max-age=31536000)
✓ Lazy loading for routes and heavy components (React.lazy / dynamic import)
✓ Image optimization (WebP/AVIF, srcset, lazy loading)
✓ Bundle analysis — flag if JS bundle > 200KB gzipped
```

### Error Handling Pattern
```typescript
// Centralized error classes
export class AppError extends Error {
  constructor(
    public statusCode: number,
    public code: string,
    message: string,
    public isOperational = true,
  ) {
    super(message);
  }
}

export class NotFoundError extends AppError {
  constructor(resource: string) {
    super(404, 'NOT_FOUND', `${resource} not found`);
  }
}

// Global error handler middleware — single place for logging + response
```

---

## 5 · UI/UX Design System

### Visual Hierarchy
- **Typography scale**: 6 sizes max (xs, sm, base, lg, xl, 2xl). Use `clamp()` for fluid type.
- **Spacing scale**: 4px base unit (4, 8, 12, 16, 24, 32, 48, 64).
- **Color palette**: 1 primary, 1 accent, 3 neutrals (bg, surface, text), semantic (success/warning/error).
- **Border radius**: consistent — pick one (4px, 8px, or 12px) and use it everywhere.

### Component Patterns
```
✓ Loading states for every async operation (skeleton > spinner)
✓ Empty states with clear CTAs
✓ Error states with retry actions
✓ Optimistic updates for instant-feel interactions
✓ Toast/notification system for feedback
✓ Debounced search inputs (300ms)
✓ Infinite scroll OR pagination — never "Load More" without count
✓ Focus management for accessibility (visible focus rings, skip links)
✓ Responsive: mobile-first, breakpoints at 640/768/1024/1280
```

### Accessibility Baseline
```
✓ Semantic HTML (nav, main, article, button — not div-for-everything)
✓ ARIA labels on icon-only buttons
✓ Color contrast ≥ 4.5:1 (AA)
✓ Keyboard navigable — all interactive elements focusable
✓ Form labels associated with inputs
✓ Alt text on meaningful images
✓ prefers-reduced-motion respected
```

### Animation Guidelines
- Duration: 150-300ms for UI transitions, 300-500ms for page transitions.
- Easing: `ease-out` for entrances, `ease-in` for exits, `ease-in-out` for state changes.
- Use `transform` and `opacity` only — never animate `width`, `height`, or `top`.
- Respect `prefers-reduced-motion: reduce`.

---

## 6 · Testing & CI/CD

### Testing Strategy
| Layer | Tool | Coverage Target | What to Test |
|---|---|---|---|
| Unit | Vitest/Jest | 80%+ critical paths | Pure logic, transformations, validators |
| Integration | Supertest | All API endpoints | Request → DB → Response cycle |
| E2E | Playwright | Critical user flows | Auth, checkout, CRUD happy paths |
| Component | Testing Library | Interactive components | User events, conditional rendering |

### Test Writing Rules
- Test behavior, not implementation. No testing private methods.
- One assertion concept per test. Multiple `expect` calls OK if testing one thing.
- Factory functions for test data — no copy-pasted fixtures.
- Mock at boundaries (DB, external APIs) — never mock the unit under test.

### CI Pipeline (GitHub Actions Default)
```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]
jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20, cache: npm }
      - run: npm ci
      - run: npm run lint          # ESLint + Prettier check
      - run: npm run typecheck     # tsc --noEmit
      - run: npm run test:unit     # Vitest
      - run: npm run test:int      # Integration (needs test DB)
      - run: npm run build         # Verify production build
    services:
      postgres:
        image: postgres:16
        env: { POSTGRES_DB: test, POSTGRES_PASSWORD: test }
        ports: ['5432:5432']
```

### Deployment Checklist
```
✓ Environment-specific configs (not .env files in production)
✓ Health check endpoint (/healthz — returns 200 + DB connectivity)
✓ Structured logging (JSON, correlation IDs, no PII)
✓ Error tracking (Sentry or equivalent)
✓ Database migrations versioned and reversible
✓ Zero-downtime deploys (rolling update or blue/green)
✓ Backup strategy for databases (daily automated + tested restore)
✓ SSL/TLS everywhere (Let's Encrypt / Cloudflare)
```

---

## 7 · Startup-Grade Execution

### Decision Framework
```
"Will this matter at 10x scale?"
  YES → Build it right (auth, data model, API contracts)
  NO  → Build it fast, flag for refactor (UI polish, admin tools)
```

### Speed Priorities
1. **Use managed services** — don't self-host what you can outsource (auth: Clerk/Auth0, email: Resend, payments: Stripe, storage: S3).
2. **Monorepo from day one** — Turborepo for shared types, validators, and config.
3. **Feature flags** — ship to production behind flags, enable progressively.
4. **Database migrations** — plan schema changes, additive-only when possible (add column → migrate data → drop old column).
5. **Observability** — logging + error tracking from day 1. Metrics and tracing can wait.

### Tech Stack Quick-Select
| Need | Default | Alternative |
|---|---|---|
| Fullstack framework | Next.js (App Router) | Remix (if heavy forms/mutations) |
| API-only backend | Express + TypeScript | Fastify (if perf-critical) |
| Database | PostgreSQL + Drizzle | MongoDB + Mongoose (document-heavy) |
| Auth | Session-based (own impl) | Clerk/Auth0 (if speed > control) |
| Hosting | Vercel (frontend) + Railway/Render (backend) | AWS (if team has DevOps) |
| CSS | Tailwind CSS v4 | Vanilla CSS (if minimal deps preferred) |
| State (client) | Zustand | Redux Toolkit (if complex state graphs) |
| Forms | React Hook Form + Zod | Conform (Remix) |

---

## Response Format

When building, follow this output structure:

```
1. Brief architecture decision (1-2 sentences)
2. Implementation code (fully working, not snippets)
3. Non-obvious notes (security, perf, edge cases) — only if needed
```

**Never output:**
- Summaries of what the user asked
- Obvious code comments (`// import express`)
- Multiple alternative approaches (pick the best one)
- Boilerplate the user didn't ask for
- Explanations of standard patterns (`this uses the middleware pattern...`)

**Always output:**
- Complete, runnable files
- Environment variable requirements
- Database migration SQL or ORM schema
- Security considerations that aren't obvious
- Performance implications of design choices

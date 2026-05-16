# 🧠 Claude Skills Library

> A curated collection of production-grade AI coding skills for Claude. Opinionated, MERN-first, TypeScript-native reference documents that enforce best practices across the full stack.

---

## 🗂️ What's Inside

```
skills/
├── 🏗️ backend/
│   ├── production-app-builder.md     — Architecture, security, code quality, deployment
│   ├── auth-system.md                — JWT, OAuth 2.0, RBAC, MFA, session patterns
│   ├── api-design.md                 — REST, GraphQL, tRPC, pagination, rate limiting
│   └── database-patterns.md          — Schema design, migrations, indexing, optimization
│
├── 🎨 frontend/
│   ├── frontend-design.md            — Design tokens, color systems, animations, glassmorphism
│   ├── react-patterns.md             — Hooks, state management, forms, API client
│   ├── performance-audit.md          — Core Web Vitals, bundle analysis, image/font optimization
│   └── component-library.md          — Design system architecture, Storybook, theming
│
├── ☁️ devops/
│   ├── docker-compose-builder.md     — Dockerfiles, multi-service compose, nginx, dev/prod
│   ├── ci-cd-pipeline.md             — GitHub Actions, Railway/Vercel/Render, preview deploys
│   └── monitoring-setup.md           — Pino logging, Sentry, health checks, alerting
│
├── 🧪 testing/
│   ├── test-writer.md                — Vitest, Supertest, Playwright, React Testing Library
│   └── mock-factory.md               — Faker factories, MSW, nock, time/service mocking
│
├── 🔧 tooling/
│   ├── mern-scaffolder.md            — Full monorepo project generator (Express + React + shared)
│   ├── code-reviewer.md              — PR checklists, security scanning, git hygiene, ADRs
│   └── debug-assistant.md            — Error analysis, Node/React/MongoDB debugging patterns
│
├── ⭐ pro/
│   ├── saas-boilerplate.md           — Multi-tenant SaaS starter (auth, billing, teams, dashboards)
│   ├── stripe-integration.md         — Payment flows, subscriptions, webhooks, customer portal
│   ├── real-time-patterns.md         — WebSockets, Socket.io, live notifications, presence
│   ├── multi-tenant-saas.md          — Tenant isolation, subdomain routing, white-labeling
│   ├── ai-integration.md             — OpenAI/Claude APIs, streaming, RAG, embeddings
│   ├── email-system.md               — Transactional emails, templates, queues, deliverability
│   ├── admin-dashboard.md            — Admin panel, user management, audit logs, analytics
│   └── deployment-playbook.md        — AWS/GCP/VPS setup, zero-downtime, auto-scaling
│
├── 🤖 ai-enterprise/
│   ├── project-contextual-assistant.md — Full-codebase RAG indexer, cross-file queries, dependency tracing
│   ├── design-to-code-synthesizer.md   — Vision-to-code, Figma integration, responsive React generation
│   ├── proactive-maintenance-advisor.md— Git hook tech debt analysis, refactoring suggestions, PR comments
│   ├── ai-testing-suite.md             — Auto test generation, sandbox execution, iterative debug loop
│   ├── domain-knowledge-assistant.md   — Domain-doc RAG, business rule enforcement, glossary validation
│   ├── devops-cicd-planner.md          — Text-to-pipeline, K8s manifests, Terraform, canary deploys
│   ├── compliance-security-auditor.md  — License scanning, OWASP SAST, SBOM, LLM security audit
│   ├── architecture-advisor.md         — Anti-pattern detection, system design review, blueprints
│   ├── code-review-facilitator.md      — PR summaries, style enforcement, reviewer assignment, ticket linking
│   └── observability-debugger.md       — Log-to-code mapping, error fingerprinting, AI root cause analysis
│
└── 🏛️ system-design/
    └── system-design-architect.md      — DDIA-based framework: data models, replication, partitioning,
                                          transactions, batch/stream processing, capacity planning
```

**35 skills** · **14,000+ lines** · **8 categories**

---

## 🚀 Quick Install

### Install everything
```bash
curl -sL https://raw.githubusercontent.com/iamzaheershaik/fullstack-claude-skill-pack/main/install.sh | bash
```

### Install by category
```bash
# Only backend skills
curl -sL ... | bash -s -- backend

# Backend + frontend
curl -sL ... | bash -s -- backend frontend

# Only pro skills
curl -sL ... | bash -s -- pro

# Only AI enterprise skills
curl -sL ... | bash -s -- ai-enterprise
```

### Install individual skills
```bash
# Just auth and Stripe
curl -sL ... | bash -s -- auth-system stripe-integration

# Just React patterns
curl -sL ... | bash -s -- react-patterns
```

### List all available skills
```bash
curl -sL ... | bash -s -- --list
```

> **Categories:** `backend` · `frontend` · `devops` · `testing` · `tooling` · `pro` · `ai-enterprise` · `system-design` · `all`
>
> Re-run anytime to change your selection — it replaces the previous install cleanly.
>
> Update: `cd ~/fullstack-claude-skill-pack && git pull`

---

## 📖 Manual Setup

### Step 1: Clone the repo

```bash
git clone https://github.com/iamzaheershaik/fullstack-claude-skill-pack.git
cd fullstack-claude-skill-pack
```

---

### 🔷 Claude Code (Terminal Agent)

#### Option A: Global Setup — All Projects (Recommended)

Apply skills to **every project** automatically:

```bash
# Create global Claude config (one-time)
mkdir -p ~/.claude

# Add to global instructions
cat >> ~/.claude/CLAUDE.md << 'EOF'

# Claude Skills
When building apps, read and follow these skill files as needed:
- ~/fullstack-claude-skill-pack/skills/backend/production-app-builder.md
- ~/fullstack-claude-skill-pack/skills/backend/auth-system.md
- ~/fullstack-claude-skill-pack/skills/backend/api-design.md
- ~/fullstack-claude-skill-pack/skills/backend/database-patterns.md
- ~/fullstack-claude-skill-pack/skills/frontend/frontend-design.md
- ~/fullstack-claude-skill-pack/skills/frontend/react-patterns.md
- ~/fullstack-claude-skill-pack/skills/frontend/performance-audit.md
- ~/fullstack-claude-skill-pack/skills/devops/docker-compose-builder.md
- ~/fullstack-claude-skill-pack/skills/testing/test-writer.md
- ~/fullstack-claude-skill-pack/skills/tooling/debug-assistant.md
- ~/fullstack-claude-skill-pack/skills/ai-enterprise/domain-knowledge-assistant.md
- ~/fullstack-claude-skill-pack/skills/ai-enterprise/compliance-security-auditor.md
- ~/fullstack-claude-skill-pack/skills/ai-enterprise/devops-cicd-planner.md
EOF
```

Claude Code will now reference these skills in **every session, every project**.

#### Option B: Per-Project Setup

Add only relevant skills to a specific project's `CLAUDE.md`:

```bash
# In your project root, create or append to CLAUDE.md
cat >> CLAUDE.md << 'EOF'

# Skills
- Read ~/fullstack-claude-skill-pack/skills/backend/auth-system.md for authentication
- Read ~/fullstack-claude-skill-pack/skills/backend/api-design.md for API design
- Read ~/fullstack-claude-skill-pack/skills/frontend/react-patterns.md for React code
EOF
```

#### Option C: Per-Prompt (One-Off)

Reference any skill directly in your prompt:

```
Read ~/fullstack-claude-skill-pack/skills/backend/auth-system.md
and implement JWT login with refresh token rotation for my Express app.
```

---

### 🔷 Claude Pro (claude.ai)

1. Go to **claude.ai** → Create a **Project**
2. Click **Project Knowledge** → Upload the `.md` files you need
3. Start chatting — Claude will follow the skills automatically

---

### 🔷 Other AI Tools (Cursor, Gemini, ChatGPT, Windsurf)

Attach any skill file as context or paste it into system/custom instructions:

```
Use the attached database-patterns.md as your reference for MongoDB schema design.
```

---

### 📖 As a Personal Reference

Each file is a standalone, dense reference document — useful even without AI:

- **Checklists** for security, deployment, accessibility
- **Decision tables** for technology choices
- **Code templates** ready to copy-paste
- **Anti-patterns** to avoid

---

## 🎯 Design Principles

| Principle | What It Means |
|---|---|
| **Production-grade** | Every pattern is deployable, not a tutorial toy |
| **MERN-first** | Defaults to MongoDB, Express, React, Node.js |
| **TypeScript-native** | All code examples in TypeScript |
| **Opinionated** | Makes decisions for you — no "it depends" without a decision matrix |
| **Token-efficient** | Dense and direct — no filler, no restating the obvious |

---

## 📋 Skill Highlights

| Skill | Key Patterns |
|---|---|
| **auth-system** | Dual-token auth (JWT + httpOnly refresh), Argon2id hashing, RBAC with ownership checks, TOTP MFA |
| **api-design** | REST envelope format, Zod validation middleware, cursor vs offset pagination, GraphQL DataLoader |
| **database-patterns** | Embedding vs referencing rules, compound indexes, zero-downtime migrations, aggregation pipelines |
| **frontend-design** | HSL color palette generator, fluid typography with `clamp()`, glassmorphism + mesh gradients, skeleton loaders |
| **react-patterns** | Zustand stores, compound components, custom hooks (debounce, media query, click outside), API client class |
| **performance-audit** | LCP/INP/CLS optimization checklists, bundle budgets, image format decision tree, font CLS prevention |
| **docker-compose-builder** | Multi-stage Dockerfile, MERN compose with health checks, nginx reverse proxy config |
| **ci-cd-pipeline** | Full GitHub Actions CI with MongoDB service, Railway/Vercel deploy workflows, monorepo Turborepo CI |
| **monitoring-setup** | Pino structured logging with redaction, Sentry with source maps, graceful shutdown handler |
| **mern-scaffolder** | Complete Turborepo monorepo template with server, client, and shared validation package |
| **debug-assistant** | Error symptom → diagnosis table, N+1 detection, memory leak checklist, event loop blocking detection |

### ⭐ Pro Skills

| Skill | Key Patterns |
|---|---|
| **saas-boilerplate** | Org/membership schema, plan config with limits, team invites, onboarding flow, usage tracking, feature flags |
| **stripe-integration** | Checkout sessions, webhook handler (idempotent), subscription management, metered billing, dunning emails |
| **real-time-patterns** | Socket.io + Redis adapter, auth on connect, live notifications, presence tracking, chat rooms |
| **multi-tenant-saas** | Tenant scoping middleware, Mongoose plugin, subdomain routing, custom domains, data isolation service |
| **ai-integration** | OpenAI/Claude streaming via SSE, RAG with vector search, prompt templates, cost controls per org |
| **email-system** | Resend + React Email templates, BullMQ queue, drip campaigns, SPF/DKIM/DMARC, bounce handling |
| **admin-dashboard** | Admin route separation, user management, impersonation, analytics aggregation, audit log with TTL |
| **deployment-playbook** | AWS ECS + ECR deploy, VPS + Caddy auto-SSL, zero-downtime rolling updates, auto-scaling policies |

### 🤖 AI Enterprise Skills

| Skill | Key Patterns |
|---|---|
| **project-contextual-assistant** | AST-based codebase indexing, vector search, cross-file dependency tracing, context-budgeted prompts |
| **design-to-code-synthesizer** | Vision model element detection, layout grid inference, React/CSS generation, Figma API, a11y audit |
| **proactive-maintenance-advisor** | Cyclomatic complexity scoring, dead code detection, duplicate finder, LLM refactoring suggestions |
| **ai-testing-suite** | Unit/integration/E2E auto-generation, sandbox runner, iterative fix loop, coverage gap analysis |
| **domain-knowledge-assistant** | Multi-format doc ingestion, semantic chunking, domain-aware code gen, glossary naming enforcer |
| **devops-cicd-planner** | Text-to-YAML pipeline gen, K8s manifests, Terraform IaC, canary/rollback, pipeline validation |
| **compliance-security-auditor** | Dependency license scan, OWASP static checks, LLM deep audit, SBOM generation, SARIF output |
| **architecture-advisor** | Anti-pattern detection (6+ rules), scaling decision tree, caching strategy, Mermaid diagram gen |
| **code-review-facilitator** | PR auto-summary, style rule enforcement, knowledge-based reviewer matching, ticket linking |
| **observability-debugger** | Structured log parsing, stack trace→code mapping, error fingerprinting, AI diagnosis, Slack alerts |

### 🏛️ System Design

| Skill | Key Patterns |
|---|---|
| **system-design-architect** | DDIA-grounded framework: requirements engineering (QPS/SLA estimation), data model selection (relational/document/graph/wide-column), storage engines (B-Tree vs LSM-Tree), replication & partitioning strategies, ACID transactions & isolation levels, batch & stream processing (Lambda/Kappa), PACELC trade-offs, consensus algorithms (Raft/Paxos), caching strategies, CQRS & event sourcing, capacity planning, anti-pattern detection |

---

## 🤝 Contributing

1. Fork the repo
2. Add or improve a skill following the existing format
3. Submit a PR with a clear description of what changed

### Skill Format Rules
- Start with a one-line description in a blockquote
- Use numbered sections with `##` headings
- Include code templates, decision tables, and checklists
- End with output format guidelines
- Keep files under 400 lines

---

## 📄 License

MIT — use freely, modify, and share.

---

**Built with 🧠 by [Zaheer Shaik](https://github.com/iamzaheershaik)**

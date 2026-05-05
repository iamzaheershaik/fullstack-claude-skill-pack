# 🧠 Claude Skills Library

> A curated collection of production-grade AI coding skills for Claude. Opinionated, MERN-first, TypeScript-native reference documents that enforce best practices across the full stack.

---

## 📦 Suggested Repository Name

```
claude-skills
```

**Alternatives:**

| Name | Vibe |
|---|---|
| `claude-skills` | Clean, simple, searchable |
| `ai-dev-skills` | Framework-agnostic branding |
| `mern-skills` | Stack-specific, precise |
| `fullstack-skill-pack` | Descriptive, community-friendly |
| `claude-playbook` | Sounds like a strategic guide |

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
└── 🔧 tooling/
    ├── mern-scaffolder.md            — Full monorepo project generator (Express + React + shared)
    ├── code-reviewer.md              — PR checklists, security scanning, git hygiene, ADRs
    └── debug-assistant.md            — Error analysis, Node/React/MongoDB debugging patterns
```

**16 skills** · **6,300+ lines** · **5 categories**

---

## 🚀 How to Use

### With Claude (Anthropic)
Add any skill as a **Project Knowledge** file in the Claude console, or reference it directly in your prompt:

```
Follow the auth-system skill to implement JWT authentication with refresh token rotation.
```

### With Gemini / Other AI Assistants
Attach a skill file as context or paste it into system instructions:

```
Use the attached database-patterns.md as your reference for MongoDB schema design.
```

### As a Personal Reference
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

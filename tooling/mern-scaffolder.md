---
name: MERN Scaffolder
category: tooling
version: 1.0.0
description: >
  Generate complete MERN stack projects. Express + MongoDB backend, React + Vite frontend, shared config, Docker, and CI/CD. Ready to develop in minutes.
author: Zaheer Shaik
tags:
  - scaffolding
  - mern
  - boilerplate
  - vite
  - tooling
---

# MERN Scaffolder — Claude Skill

> Generate complete MERN stack projects. Express + MongoDB backend, React + Vite frontend, shared config, Docker, CI/CD. Ready to develop in minutes.

---

## Core Directives

1. **Zero to running in 5 minutes.** Clone, install, start — everything works.
2. **Production-ready from scaffold.** Not a toy — includes auth, error handling, logging.
3. **Convention over configuration.** Sane defaults, override only when needed.
4. **Monorepo by default.** Shared types, validation, and config between client and server.

---

## 1 · Project Structure

### Monorepo Layout
```
project-root/
├── apps/
│   ├── server/                  # Express + MongoDB API
│   │   ├── src/
│   │   │   ├── config/          # env validation, database connection
│   │   │   │   ├── env.ts
│   │   │   │   └── database.ts
│   │   │   ├── modules/         # feature-based modules
│   │   │   │   ├── auth/
│   │   │   │   │   ├── auth.controller.ts
│   │   │   │   │   ├── auth.service.ts
│   │   │   │   │   ├── auth.routes.ts
│   │   │   │   │   └── auth.test.ts
│   │   │   │   └── user/
│   │   │   │       ├── user.model.ts
│   │   │   │       ├── user.controller.ts
│   │   │   │       ├── user.service.ts
│   │   │   │       └── user.routes.ts
│   │   │   ├── middleware/
│   │   │   │   ├── authenticate.ts
│   │   │   │   ├── errorHandler.ts
│   │   │   │   ├── validate.ts
│   │   │   │   └── rateLimiter.ts
│   │   │   ├── lib/
│   │   │   │   ├── errors.ts
│   │   │   │   └── logger.ts
│   │   │   └── app.ts           # Express app (no listen)
│   │   │   └── server.ts        # Bootstrap + listen
│   │   ├── package.json
│   │   ├── tsconfig.json
│   │   └── Dockerfile
│   │
│   └── client/                  # React + Vite SPA
│       ├── src/
│       │   ├── components/
│       │   │   ├── ui/          # Button, Input, Card, etc.
│       │   │   └── layout/      # Header, Sidebar, Footer
│       │   ├── features/        # Feature modules
│       │   │   └── auth/
│       │   │       ├── LoginForm.tsx
│       │   │       ├── RegisterForm.tsx
│       │   │       └── useAuth.ts
│       │   ├── hooks/           # Shared hooks
│       │   ├── lib/
│       │   │   ├── api.ts       # API client
│       │   │   └── utils.ts
│       │   ├── stores/          # Zustand stores
│       │   ├── styles/
│       │   │   └── index.css    # Design tokens + global styles
│       │   ├── App.tsx
│       │   └── main.tsx
│       ├── package.json
│       ├── tsconfig.json
│       ├── vite.config.ts
│       └── Dockerfile
│
├── packages/
│   └── shared/                  # Shared types + validators
│       ├── src/
│       │   ├── types/
│       │   │   └── user.ts
│       │   └── validators/
│       │       └── auth.ts
│       ├── package.json
│       └── tsconfig.json
│
├── docker-compose.yml
├── docker-compose.prod.yml
├── .github/workflows/ci.yml
├── .gitignore
├── .env.example
├── package.json                 # Root (workspaces)
├── turbo.json
└── README.md
```

---

## 2 · Root Configuration

### package.json (Root)
```json
{
  "name": "myapp",
  "private": true,
  "workspaces": ["apps/*", "packages/*"],
  "scripts": {
    "dev": "turbo run dev",
    "build": "turbo run build",
    "lint": "turbo run lint",
    "typecheck": "turbo run typecheck",
    "test": "turbo run test",
    "docker:dev": "docker compose up -d",
    "docker:down": "docker compose down"
  },
  "devDependencies": {
    "turbo": "^2.0.0",
    "typescript": "^5.4.0"
  }
}
```

### turbo.json
```json
{
  "$schema": "https://turbo.build/schema.json",
  "tasks": {
    "dev": { "persistent": true, "cache": false },
    "build": { "dependsOn": ["^build"], "outputs": ["dist/**"] },
    "lint": {},
    "typecheck": { "dependsOn": ["^build"] },
    "test": { "dependsOn": ["build"] }
  }
}
```

### .env.example
```env
# Server
NODE_ENV=development
PORT=3000
MONGO_URI=mongodb://localhost:27017/myapp
REDIS_URL=redis://localhost:6379
JWT_ACCESS_SECRET=change-this-to-a-random-256-bit-string
ALLOWED_ORIGINS=http://localhost:5173

# Client
VITE_API_URL=http://localhost:3000/api/v1
```

### .gitignore
```
node_modules/
dist/
.env
.env.local
.env.production
coverage/
*.log
.turbo/
.DS_Store
```

---

## 3 · Server Scaffold

### Environment Config
```typescript
// apps/server/src/config/env.ts
import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  PORT: z.coerce.number().default(3000),
  MONGO_URI: z.string().url(),
  REDIS_URL: z.string().optional(),
  JWT_ACCESS_SECRET: z.string().min(32),
  ALLOWED_ORIGINS: z.string().transform(s => s.split(',')),
});

export const env = envSchema.parse(process.env);
```

### Express App
```typescript
// apps/server/src/app.ts
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import cookieParser from 'cookie-parser';
import { env } from './config/env';
import { errorHandler } from './middleware/errorHandler';
import { requestLogger } from './middleware/requestLogger';
import { authRoutes } from './modules/auth/auth.routes';
import { userRoutes } from './modules/user/user.routes';

const app = express();

app.use(helmet());
app.use(cors({ origin: env.ALLOWED_ORIGINS, credentials: true }));
app.use(express.json({ limit: '10mb' }));
app.use(cookieParser());
app.use(requestLogger);

// Health check
app.get('/healthz', (_req, res) => res.json({ status: 'ok' }));

// Routes
app.use('/api/v1/auth', authRoutes);
app.use('/api/v1/users', userRoutes);

// Error handler (must be last)
app.use(errorHandler);

export { app };
```

### Server Bootstrap
```typescript
// apps/server/src/server.ts
import { app } from './app';
import { env } from './config/env';
import { connectDB } from './config/database';
import { logger } from './lib/logger';

async function bootstrap() {
  await connectDB();
  const server = app.listen(env.PORT, () => {
    logger.info(`Server running on port ${env.PORT} [${env.NODE_ENV}]`);
  });

  // Graceful shutdown
  const shutdown = async (signal: string) => {
    logger.info({ signal }, 'Shutting down...');
    server.close(async () => {
      await mongoose.connection.close();
      process.exit(0);
    });
    setTimeout(() => process.exit(1), 30000);
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

bootstrap().catch((err) => {
  logger.fatal(err, 'Failed to start');
  process.exit(1);
});
```

### Error Handler
```typescript
// apps/server/src/middleware/errorHandler.ts
import type { ErrorRequestHandler } from 'express';
import { ZodError } from 'zod';
import { AppError } from '../lib/errors';

export const errorHandler: ErrorRequestHandler = (err, req, res, _next) => {
  // Zod validation errors
  if (err instanceof ZodError) {
    return res.status(400).json({
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Invalid input',
        details: err.issues.map(i => ({ field: i.path.join('.'), issue: i.message })),
      },
    });
  }

  // Known application errors
  if (err instanceof AppError) {
    return res.status(err.statusCode).json({
      error: { code: err.code, message: err.message },
    });
  }

  // Unknown errors
  req.log?.error({ err }, 'Unhandled error');
  res.status(500).json({
    error: { code: 'INTERNAL_ERROR', message: 'Something went wrong' },
  });
};
```

---

## 4 · Client Scaffold

### Vite Config
```typescript
// apps/client/vite.config.ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
  server: {
    port: 5173,
    proxy: {
      '/api': { target: 'http://localhost:3000', changeOrigin: true },
    },
  },
});
```

### App Entry
```tsx
// apps/client/src/App.tsx
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { Suspense, lazy } from 'react';
import { Layout } from '@/components/layout/Layout';
import { PageSkeleton } from '@/components/ui/PageSkeleton';

const Home = lazy(() => import('@/pages/Home'));
const Login = lazy(() => import('@/pages/Login'));
const Dashboard = lazy(() => import('@/pages/Dashboard'));

export function App() {
  return (
    <BrowserRouter>
      <Layout>
        <Suspense fallback={<PageSkeleton />}>
          <Routes>
            <Route path="/" element={<Home />} />
            <Route path="/login" element={<Login />} />
            <Route path="/dashboard" element={<Dashboard />} />
          </Routes>
        </Suspense>
      </Layout>
    </BrowserRouter>
  );
}
```

---

## 5 · Shared Package

```typescript
// packages/shared/src/validators/auth.ts
import { z } from 'zod';

export const LoginSchema = z.object({
  email: z.string().email().trim().toLowerCase(),
  password: z.string().min(1),
});

export const RegisterSchema = z.object({
  email: z.string().email().trim().toLowerCase().max(255),
  password: z.string().min(8).max(128),
  name: z.string().trim().min(1).max(100),
});

export type LoginInput = z.infer<typeof LoginSchema>;
export type RegisterInput = z.infer<typeof RegisterSchema>;

// packages/shared/src/types/user.ts
export interface User {
  id: string;
  email: string;
  name: string;
  role: 'user' | 'admin' | 'moderator';
}
```

---

## 6 · Scaffold Checklist

### Before First Commit
```
✓ All env vars documented in .env.example
✓ .gitignore covers node_modules, dist, .env, coverage
✓ README has: setup instructions, env vars table, scripts table
✓ Health check endpoint works
✓ Error handler catches all error types
✓ CORS configured for local dev
✓ TypeScript strict mode enabled
✓ ESLint + Prettier configured
✓ At least one test runs
✓ docker compose up starts all services
```

### README Template
```markdown
# Project Name

Brief description.

## Quick Start

\`\`\`bash
git clone <repo>
cp .env.example .env
docker compose up -d     # starts MongoDB + Redis
npm install
npm run dev              # starts server + client
\`\`\`

## Scripts

| Script | Description |
|---|---|
| `npm run dev` | Start all services in dev mode |
| `npm run build` | Build all packages |
| `npm run test` | Run all tests |
| `npm run lint` | Lint all packages |

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `MONGO_URI` | Yes | - | MongoDB connection string |
| `JWT_ACCESS_SECRET` | Yes | - | JWT signing secret (min 32 chars) |
| `PORT` | No | 3000 | Server port |
```

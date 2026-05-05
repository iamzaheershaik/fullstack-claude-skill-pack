# CI/CD Pipeline — Claude Skill

> Build automated CI/CD pipelines. GitHub Actions, deployment to Railway/Vercel/Render, preview deploys, database migrations, rollbacks.

---

## Core Directives

1. **Automate everything.** If you do it twice, script it. If it's critical, CI it.
2. **Fail fast.** Lint → typecheck → test (cheapest first). Don't waste time building if code is broken.
3. **Deploy immutably.** Every deploy is a new artifact — never patch in place.
4. **Rollback in seconds.** If deploy fails, previous version must be one command away.

---

## 1 · GitHub Actions — Full CI Pipeline

### Node.js + MongoDB CI
```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

env:
  NODE_VERSION: '20'

jobs:
  lint-and-type-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: 'npm'
      - run: npm ci
      - run: npm run lint
      - run: npm run typecheck

  test:
    runs-on: ubuntu-latest
    needs: lint-and-type-check
    services:
      mongo:
        image: mongo:7
        ports: ['27017:27017']
        options: >-
          --health-cmd="echo 'db.runCommand(\"ping\").ok' | mongosh --quiet"
          --health-interval=10s
          --health-timeout=5s
          --health-retries=5
      redis:
        image: redis:7-alpine
        ports: ['6379:6379']
        options: >-
          --health-cmd="redis-cli ping"
          --health-interval=10s
          --health-timeout=5s
          --health-retries=5
    env:
      MONGO_URI: mongodb://localhost:27017/test
      REDIS_URL: redis://localhost:6379
      JWT_ACCESS_SECRET: test-secret-not-for-production
      NODE_ENV: test
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: 'npm'
      - run: npm ci
      - run: npm run test:unit -- --coverage
      - run: npm run test:integration
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: coverage
          path: coverage/

  build:
    runs-on: ubuntu-latest
    needs: test
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: 'npm'
      - run: npm ci
      - run: npm run build
      - uses: actions/upload-artifact@v4
        with:
          name: build
          path: dist/
```

---

## 2 · Deployment Workflows

### Deploy to Railway
```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    needs: [lint-and-type-check, test, build]  # From CI workflow
    steps:
      - uses: actions/checkout@v4
      - uses: railwayapp/railway-action@v1
        with:
          service: api
        env:
          RAILWAY_TOKEN: ${{ secrets.RAILWAY_TOKEN }}
```

### Deploy to Vercel (Frontend)
```yaml
# Vercel auto-deploys from GitHub — use vercel.json for config
# For manual control:
name: Deploy Frontend

on:
  push:
    branches: [main]
    paths: ['client/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: amondnet/vercel-action@v25
        with:
          vercel-token: ${{ secrets.VERCEL_TOKEN }}
          vercel-org-id: ${{ secrets.VERCEL_ORG_ID }}
          vercel-project-id: ${{ secrets.VERCEL_PROJECT_ID }}
          vercel-args: '--prod'
          working-directory: ./client
```

### Deploy to Render
```yaml
# render.yaml (Blueprint)
services:
  - type: web
    name: api
    runtime: node
    region: oregon
    plan: starter
    buildCommand: npm ci && npm run build
    startCommand: node dist/index.js
    healthCheckPath: /healthz
    envVars:
      - key: NODE_ENV
        value: production
      - key: MONGO_URI
        fromDatabase:
          name: myapp-db
          property: connectionString

databases:
  - name: myapp-db
    plan: starter
```

### Docker Deploy (Self-hosted / VPS)
```yaml
name: Deploy Docker

on:
  push:
    branches: [main]

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v5
        with:
          push: true
          tags: ghcr.io/${{ github.repository }}/api:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy:
    runs-on: ubuntu-latest
    needs: build-and-push
    steps:
      - name: Deploy to server
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: deploy
          key: ${{ secrets.SSH_KEY }}
          script: |
            docker pull ghcr.io/${{ github.repository }}/api:${{ github.sha }}
            docker compose -f docker-compose.prod.yml up -d --no-deps api
```

---

## 3 · Preview Deployments

### Vercel Preview (Automatic)
```json
// vercel.json
{
  "github": {
    "autoAlias": true,
    "silent": true
  }
}
// Every PR gets a preview URL automatically
```

### Custom Preview with GitHub Actions
```yaml
name: Preview Deploy

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  preview:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci && npm run build
      - name: Deploy preview
        id: deploy
        run: |
          PREVIEW_URL=$(npx vercel --token ${{ secrets.VERCEL_TOKEN }})
          echo "url=$PREVIEW_URL" >> $GITHUB_OUTPUT
      - name: Comment PR with preview URL
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `🚀 Preview deployed: ${{ steps.deploy.outputs.url }}`
            })
```

---

## 4 · Database Migrations in CI

```yaml
# Run migrations before deploy
migrate:
  runs-on: ubuntu-latest
  needs: test
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-node@v4
      with:
        node-version: 20
        cache: 'npm'
    - run: npm ci
    - name: Run migrations
      env:
        MONGO_URI: ${{ secrets.PRODUCTION_MONGO_URI }}
      run: npm run migrate:up
```

### Migration Safety
```
✓ Run migrations BEFORE deploying new code
✓ Migrations must be backward-compatible with current running code
✓ Test migrations on staging database first
✓ Have a rollback plan (down migration) for every up migration
✓ Never drop columns/tables that current code references
```

---

## 5 · Secrets Management

### GitHub Secrets Setup
```
Repository → Settings → Secrets → Actions

Required secrets:
├── RAILWAY_TOKEN          # Railway deployment
├── VERCEL_TOKEN           # Vercel deployment
├── PRODUCTION_MONGO_URI   # Production database
├── SENTRY_DSN             # Error tracking
├── JWT_ACCESS_SECRET      # Auth secret
└── SSH_KEY                # VPS deployment
```

### Environment-Specific Secrets
```yaml
# Use GitHub Environments for staging/production
deploy:
  runs-on: ubuntu-latest
  environment: production   # Requires approval + has its own secrets
  steps:
    - run: echo "Deploying with ${{ secrets.MONGO_URI }}"  # production MONGO_URI
```

### Rules
```
✓ Never echo secrets in CI logs
✓ Use GitHub Environments for production (require approval)
✓ Rotate secrets every 90 days
✓ Use OIDC tokens instead of long-lived secrets where possible
✗ Never commit .env files
✗ Never use personal API keys in shared CI
```

---

## 6 · Monorepo CI (Turborepo)

```yaml
name: CI (Monorepo)

on:
  push:
    branches: [main]
  pull_request:

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2   # Needed for turbo affected
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'npm'
      - run: npm ci
      - run: npx turbo run lint typecheck test build --filter=...[HEAD~1]
        # Only runs tasks for packages that changed
```

### turbo.json
```json
{
  "tasks": {
    "build": { "dependsOn": ["^build"], "outputs": ["dist/**"] },
    "test": { "dependsOn": ["build"] },
    "lint": {},
    "typecheck": {}
  }
}
```

---

## 7 · Rollback Strategies

| Strategy | Speed | Complexity | Use When |
|---|---|---|---|
| Revert commit + redeploy | ~5min | Low | Simple apps |
| Deploy previous tag | ~2min | Low | Tagged releases |
| Blue/green switch | Instant | Medium | Zero-downtime critical |
| Feature flag toggle | Instant | Medium | Partial rollback |

### Tag-Based Rollback
```bash
# Deploy specific tag
git tag v1.2.3
git push origin v1.2.3

# Rollback: deploy previous tag
git checkout v1.2.2
# Trigger deploy workflow

# Or in GitHub Actions:
on:
  workflow_dispatch:
    inputs:
      tag:
        description: 'Tag to deploy'
        required: true
```

### Deployment Checklist
```
✓ CI passes (lint + typecheck + tests)
✓ Build succeeds
✓ Migrations run without errors
✓ Health check passes after deploy
✓ Smoke tests pass on production
✓ Monitoring shows no error spike
✓ Rollback plan tested and ready
```

---
name: Integrated DevOps/CICD Planner
category: ai-enterprise
version: 1.0.0
description: >
  Generate CI/CD pipeline configs, Kubernetes manifests, Terraform scripts, and deployment plans from natural language. Supports GitHub Actions, GitLab CI, AWS, GCP. Node.js/TypeScript.
author: Zaheer Shaik
tags:
  - devops
  - ci-cd
  - kubernetes
  - terraform
  - enterprise
---

# Integrated DevOps/CICD Planner — Claude Skill (AI Enterprise)

> Generate CI/CD pipeline configs, Kubernetes manifests, Terraform scripts, and deployment plans from natural language. Supports GitHub Actions, GitLab CI, AWS, GCP. Node.js/TypeScript.

---

## Core Directives

1. **Automate the pipeline, not the decision.** Generate configs, but require human approval before deploying.
2. **Progressive delivery by default.** Every pipeline includes canary/rollback. No yolo deploys.
3. **Platform-agnostic core.** Templates work across GitHub Actions, GitLab CI, and cloud providers.
4. **Infrastructure as Code only.** No manual console clicks — everything version-controlled.

---

## 1 · Pipeline Generator

### Text-to-Pipeline Engine
```typescript
import OpenAI from 'openai';
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

interface PipelineSpec {
  platform: 'github-actions' | 'gitlab-ci' | 'azure-devops';
  runtime: string;       // e.g., 'node:20', 'python:3.12'
  stages: string[];      // e.g., ['lint', 'test', 'build', 'deploy']
  services?: string[];   // e.g., ['postgres', 'redis', 'mongodb']
  deployTarget: 'kubernetes' | 'ecs' | 'vercel' | 'railway' | 'vps';
  environments: string[];// e.g., ['staging', 'production']
  features: string[];    // e.g., ['canary', 'rollback', 'preview-deploys']
}

export async function generatePipeline(description: string): Promise<{
  spec: PipelineSpec;
  config: string;
  explanation: string;
}> {
  const response = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages: [
      {
        role: 'system',
        content: `You are a senior DevOps engineer. Generate a CI/CD pipeline from the description.
Return JSON with:
1. "spec": parsed pipeline specification
2. "config": the YAML pipeline configuration (complete, production-ready)
3. "explanation": brief rationale for key decisions

Pipeline rules:
- Always include: lint, type-check, test, build stages
- Always add health checks and timeouts
- Include caching for dependencies (npm, pip, etc.)
- Add concurrency controls (cancel in-progress on new push)
- Separate staging and production environments
- Add manual approval gate before production deploy
- Include rollback step on failure`,
      },
      { role: 'user', content: description },
    ],
    max_tokens: 4000,
    temperature: 0.2,
    response_format: { type: 'json_object' },
  });

  return JSON.parse(response.choices[0].message.content || '{}');
}
```

### GitHub Actions Template Library
```yaml
# Template: Node.js Full Pipeline
name: CI/CD
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

env:
  NODE_VERSION: '20'
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  quality:
    runs-on: ubuntu-latest
    services:
      mongodb:
        image: mongo:7
        ports: ['27017:27017']
      redis:
        image: redis:7-alpine
        ports: ['6379:6379']
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: npm
      - run: npm ci
      - run: npm run lint
      - run: npm run typecheck
      - run: npm run test:unit -- --coverage
      - run: npm run test:integration
      - uses: actions/upload-artifact@v4
        with:
          name: coverage
          path: coverage/

  build:
    needs: quality
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v5
        with:
          push: true
          tags: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy-staging:
    needs: build
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v4
      - run: |
          # Deploy to staging cluster
          kubectl set image deployment/app \
            app=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} \
            --namespace=staging
          kubectl rollout status deployment/app --namespace=staging --timeout=300s

  deploy-production:
    needs: deploy-staging
    runs-on: ubuntu-latest
    environment:
      name: production
      url: https://app.example.com
    steps:
      - uses: actions/checkout@v4
      - run: |
          # Canary deploy (10% traffic)
          kubectl set image deployment/app-canary \
            app=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} \
            --namespace=production
          # Wait and verify health
          sleep 60
          HEALTH=$(curl -s -o /dev/null -w "%{http_code}" https://app.example.com/healthz)
          if [ "$HEALTH" != "200" ]; then
            kubectl rollout undo deployment/app-canary --namespace=production
            exit 1
          fi
          # Full rollout
          kubectl set image deployment/app \
            app=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} \
            --namespace=production
          kubectl rollout status deployment/app --namespace=production --timeout=300s
```

---

## 2 · Kubernetes Manifest Generator

### Deployment + Service Template
```typescript
export function generateK8sManifest(config: {
  name: string;
  image: string;
  port: number;
  replicas: number;
  env: Record<string, string>;
  resources: { cpuRequest: string; memRequest: string; cpuLimit: string; memLimit: string };
}): string {
  return `apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${config.name}
  labels:
    app: ${config.name}
spec:
  replicas: ${config.replicas}
  selector:
    matchLabels:
      app: ${config.name}
  template:
    metadata:
      labels:
        app: ${config.name}
    spec:
      containers:
        - name: ${config.name}
          image: ${config.image}
          ports:
            - containerPort: ${config.port}
          env:
${Object.entries(config.env).map(([k, v]) => `            - name: ${k}\n              value: "${v}"`).join('\n')}
          resources:
            requests:
              cpu: ${config.resources.cpuRequest}
              memory: ${config.resources.memRequest}
            limits:
              cpu: ${config.resources.cpuLimit}
              memory: ${config.resources.memLimit}
          livenessProbe:
            httpGet:
              path: /healthz
              port: ${config.port}
            initialDelaySeconds: 15
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /healthz
              port: ${config.port}
            initialDelaySeconds: 5
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: ${config.name}
spec:
  selector:
    app: ${config.name}
  ports:
    - port: 80
      targetPort: ${config.port}
  type: ClusterIP`;
}
```

---

## 3 · Terraform IaC Generator

### AWS Infrastructure Template
```typescript
export function generateTerraform(config: {
  provider: 'aws' | 'gcp' | 'azure';
  region: string;
  services: ('ecs' | 'rds' | 'redis' | 's3' | 'cloudfront')[];
}): string {
  const blocks: string[] = [
    `provider "${config.provider}" {\n  region = "${config.region}"\n}`,
  ];

  if (config.services.includes('ecs')) {
    blocks.push(`
resource "aws_ecs_cluster" "main" {
  name = "app-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_service" "app" {
  name            = "app-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets         = var.private_subnets
    security_groups = [aws_security_group.ecs.id]
  }
}`);
  }

  if (config.services.includes('rds')) {
    blocks.push(`
resource "aws_db_instance" "main" {
  identifier          = "app-db"
  engine              = "postgres"
  engine_version      = "16"
  instance_class      = "db.t3.medium"
  allocated_storage   = 20
  storage_encrypted   = true
  multi_az            = true
  skip_final_snapshot = false
  backup_retention_period = 7
  deletion_protection = true
}`);
  }

  return blocks.join('\n\n');
}
```

---

## 4 · Pipeline Validation

### Config Validator
```typescript
export function validatePipeline(yaml: string, platform: string) {
  const errors: string[] = [];
  const warnings: string[] = [];
  // Common checks
  if (!yaml.includes('timeout')) warnings.push('No timeout — add timeouts to prevent hung jobs');
  if (!yaml.includes('cache')) warnings.push('No dependency caching — builds will be slower');
  if (!yaml.includes('concurrency') && platform === 'github-actions') warnings.push('No concurrency control');
  // Security checks
  if (yaml.includes('${{ github.event.pull_request.head.ref }}')) errors.push('SECURITY: PR head ref in commands — injection risk');
  if (/secrets\.\w+/.test(yaml) && yaml.includes('pull_request_target')) errors.push('SECURITY: Secrets exposed in pull_request_target');
  // Best practices
  if (!yaml.includes('healthz') && !yaml.includes('health')) warnings.push('No health check — add liveness/readiness probes');
  if (!yaml.includes('rollback') && !yaml.includes('undo')) warnings.push('No rollback strategy');
  return { valid: errors.length === 0, errors, warnings };
}
```

---

## 5 · DevOps Decision Matrix

| Scenario | CI Platform | Deploy Target | Strategy |
|---|---|---|---|
| Startup MVP | GitHub Actions | Railway/Vercel | Auto-deploy on push |
| Growing team | GitHub Actions | Kubernetes (EKS) | Canary + manual approval |
| Enterprise | GitLab CI | ECS/EKS | Blue-green + compliance gates |
| Open source | GitHub Actions | GitHub Pages / Vercel | Auto-deploy + preview |
| Multi-cloud | GitLab CI | Terraform + multi-cloud | Progressive + feature flags |

### Resource Sizing: Dev `250m/256Mi×1` · Small `500m/512Mi×2` · Medium `1cpu/1Gi×3` · Large `2cpu/2Gi×5`

---

## 6 · DevOps Planner Checklist

```
Pipeline:
✓ Lint → Type-check → Test → Build → Deploy stages
✓ Dependency caching (npm/pip/docker layers)
✓ Concurrency controls (cancel previous runs)
✓ Timeout on every job (prevent hung pipelines)
✓ Artifact upload (coverage, build outputs)

Deployment:
✓ Separate staging and production environments
✓ Manual approval gate before production
✓ Canary or blue-green deployment strategy
✓ Automatic rollback on health check failure
✓ Zero-downtime rolling updates

Infrastructure:
✓ IaC (Terraform/Pulumi) for all resources
✓ Encrypted secrets management
✓ Health check endpoints (/healthz)
✓ Resource limits (CPU, memory)
✓ Auto-scaling policies

Security:
✗ Never expose secrets in logs or PR contexts
✓ Pin action versions (@v4, not @main)
✓ Least-privilege IAM roles
✓ Container image scanning
```

---

## Response Format

Output: (1) Parsed spec (platform, stages, targets) → (2) Config files (YAML/Terraform/K8s) → (3) Validation results → (4) Strategy rationale.

**Never output:** configs without health checks, pipelines without rollback, hardcoded secrets.
**Always output:** caching, concurrency, timeouts, approval gates, rollback strategy.

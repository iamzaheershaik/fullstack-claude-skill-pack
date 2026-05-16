---
name: Deployment Playbook
category: pro
version: 1.0.0
description: >
  Deploy and scale production apps. AWS/GCP setup, zero-downtime deploys, auto-scaling, CDN, SSL, DNS, backup strategies, and incident response.
author: Zaheer Shaik
tags:
  - deployment
  - aws
  - scaling
  - production
  - pro
---

# Deployment Playbook — Claude Skill (Pro)

> Deploy and scale production apps. AWS/GCP setup, zero-downtime deploys, auto-scaling, CDN, SSL, DNS, backup strategies, incident response.

---

## Core Directives

1. **Automate every deploy.** If it requires SSH and manual commands, it's not production-ready.
2. **Zero downtime or don't deploy.** Rolling updates, blue-green, or canary — never cold restart.
3. **Monitor before you scale.** Know your bottleneck before throwing servers at it.
4. **Plan for failure.** Every component will fail — have runbooks for each.

---

## 1 · Hosting Decision Matrix

### Platform Selection
| Platform | Best For | Cost | Complexity | Auto-Scale |
|---|---|---|---|---|
| **Vercel** | Frontend, Next.js | Free → $20/mo | Lowest | Yes |
| **Railway** | Backend, databases | $5/mo+ | Low | Yes |
| **Render** | Full stack | Free → $7/mo | Low | Yes |
| **Fly.io** | Global edge, containers | $0+ usage | Medium | Yes |
| **AWS (ECS/Lambda)** | Enterprise, full control | Variable | High | Yes |
| **GCP (Cloud Run)** | Containers, auto-scale | $0+ usage | Medium | Yes |
| **VPS (Hetzner/DigitalOcean)** | Budget, full control | $4-40/mo | Medium | No |

### Default Stack Recommendation
```
Indie / MVP:        Vercel (frontend) + Railway (backend + DB)
Startup:            Vercel + AWS ECS (backend) + Atlas (DB) + CloudFront (CDN)
Scale:              AWS ECS/EKS + RDS/Atlas + ElastiCache + CloudFront
Budget:             Hetzner VPS + Docker + Caddy + managed DB
```

---

## 2 · AWS Production Setup

### Architecture
```
                    ┌──────────────┐
                    │  CloudFront  │  (CDN + SSL)
                    └──────┬───────┘
                           │
               ┌───────────┼───────────┐
               │                       │
        ┌──────┴──────┐         ┌──────┴──────┐
        │   S3 Bucket │         │     ALB     │  (Load Balancer)
        │  (Frontend) │         └──────┬──────┘
        └─────────────┘                │
                              ┌────────┼────────┐
                              │                  │
                       ┌──────┴──────┐   ┌──────┴──────┐
                       │  ECS Task 1 │   │  ECS Task 2 │
                       └──────┬──────┘   └──────┬──────┘
                              │                  │
                    ┌─────────┼──────────────────┼─────────┐
                    │                                      │
             ┌──────┴──────┐                       ┌──────┴──────┐
             │   MongoDB   │                       │    Redis     │
             │   (Atlas)   │                       │ (ElastiCache)│
             └─────────────┘                       └──────────────┘
```

### ECS Service Definition
```yaml
# ecs-task-definition.json
{
  "family": "myapp-api",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "containerDefinitions": [
    {
      "name": "api",
      "image": "${ECR_REGISTRY}/myapp-api:${IMAGE_TAG}",
      "portMappings": [{ "containerPort": 3000 }],
      "healthCheck": {
        "command": ["CMD-SHELL", "wget -qO- http://localhost:3000/healthz || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 10
      },
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/myapp-api",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "secrets": [
        { "name": "MONGO_URI", "valueFrom": "arn:aws:ssm:us-east-1:123:parameter/myapp/MONGO_URI" },
        { "name": "JWT_ACCESS_SECRET", "valueFrom": "arn:aws:ssm:us-east-1:123:parameter/myapp/JWT_SECRET" }
      ]
    }
  ]
}
```

### GitHub Actions → ECR → ECS Deploy
```yaml
name: Deploy to AWS

on:
  push:
    branches: [main]

env:
  AWS_REGION: us-east-1
  ECR_REPO: myapp-api
  ECS_CLUSTER: myapp-cluster
  ECS_SERVICE: myapp-api-service

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123:role/github-actions
          aws-region: ${{ env.AWS_REGION }}

      - uses: aws-actions/amazon-ecr-login@v2
        id: ecr

      - name: Build and push
        run: |
          IMAGE="${{ steps.ecr.outputs.registry }}/${{ env.ECR_REPO }}:${{ github.sha }}"
          docker build -t $IMAGE ./server
          docker push $IMAGE
          echo "image=$IMAGE" >> $GITHUB_OUTPUT
        id: build

      - name: Deploy to ECS
        run: |
          aws ecs update-service \
            --cluster ${{ env.ECS_CLUSTER }} \
            --service ${{ env.ECS_SERVICE }} \
            --force-new-deployment
```

---

## 3 · VPS Deployment (Budget Option)

### Setup Script
```bash
#!/bin/bash
# Initial VPS setup (Ubuntu 22.04)

# Security
apt update && apt upgrade -y
ufw allow 22/tcp && ufw allow 80/tcp && ufw allow 443/tcp && ufw enable

# Create deploy user
adduser --disabled-password deploy
usermod -aG docker deploy

# Install Docker
curl -fsSL https://get.docker.com | sh

# Install Caddy (reverse proxy + auto SSL)
apt install -y caddy
```

### Caddy Config (Auto SSL)
```
# /etc/caddy/Caddyfile
yourapp.com {
  # Frontend
  handle /* {
    root * /var/www/myapp/client
    file_server
    try_files {path} /index.html
  }

  # API proxy
  handle /api/* {
    reverse_proxy localhost:3000
  }

  # Security headers
  header {
    X-Frame-Options SAMEORIGIN
    X-Content-Type-Options nosniff
    Referrer-Policy strict-origin-when-cross-origin
  }
}
```

### Deploy Script
```bash
#!/bin/bash
# deploy.sh — run on server or via SSH from CI
set -e

cd /opt/myapp
git pull origin main
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d --remove-orphans

# Wait for health check
sleep 5
curl -sf http://localhost:3000/healthz || { echo "Health check failed!"; exit 1; }
echo "✅ Deployed successfully"
```

---

## 4 · Zero-Downtime Deployment

### Rolling Update (Docker Compose)
```yaml
services:
  api:
    deploy:
      replicas: 2
      update_config:
        parallelism: 1        # update one at a time
        delay: 10s
        order: start-first    # start new before stopping old
      rollback_config:
        parallelism: 0
        order: stop-first
```

### Blue-Green Deployment
```bash
# Start new version on different port
docker compose -f docker-compose.green.yml up -d

# Test new version
curl -sf http://localhost:3001/healthz

# Switch nginx/Caddy upstream to new version
# Verify traffic flows correctly

# Stop old version
docker compose -f docker-compose.blue.yml down
```

### Graceful Shutdown (Required for Zero-Downtime)
```typescript
process.on('SIGTERM', () => {
  logger.info('SIGTERM received — draining connections');
  server.close(async () => {
    await mongoose.connection.close();
    await redisClient.quit();
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 30000); // force after 30s
});
```

---

## 5 · SSL & DNS

### SSL Options
| Method | Effort | Cost | Best For |
|---|---|---|---|
| Caddy (auto) | Zero config | Free | VPS |
| Let's Encrypt + certbot | Low | Free | Nginx on VPS |
| CloudFront / Cloudflare | Zero config | Free | CDN + proxy |
| AWS ACM | Low | Free | AWS services |

### DNS Setup
```
Type   Name           Value                    TTL
A      yourapp.com    <server-ip>              300
CNAME  www            yourapp.com              300
CNAME  api            yourapp.com              300
A      *.yourapp.com  <server-ip>              300  (wildcard for subdomains)
TXT    _dmarc         v=DMARC1; p=quarantine   3600
TXT    @              v=spf1 include:...        3600
```

---

## 6 · Auto-Scaling

### AWS ECS Auto-Scaling
```json
{
  "scalableTarget": {
    "minCapacity": 2,
    "maxCapacity": 10,
    "resourceId": "service/myapp-cluster/myapp-api"
  },
  "scalingPolicy": {
    "policyType": "TargetTrackingScaling",
    "targetTrackingScalingPolicyConfiguration": {
      "targetValue": 70.0,
      "predefinedMetricSpecification": {
        "predefinedMetricType": "ECSServiceAverageCPUUtilization"
      },
      "scaleInCooldown": 300,
      "scaleOutCooldown": 60
    }
  }
}
```

### When to Scale
| Metric | Scale Out | Scale In |
|---|---|---|
| CPU | > 70% for 2 min | < 30% for 10 min |
| Memory | > 80% for 2 min | < 40% for 10 min |
| Request count | > 1000 req/min/instance | < 200 req/min/instance |
| Response time | P95 > 2s for 5 min | P95 < 500ms for 10 min |

---

## 7 · Backup & Disaster Recovery

### Backup Strategy
| Data | Method | Frequency | Retention | Location |
|---|---|---|---|---|
| MongoDB | Atlas auto-backup | Continuous | 30 days | Different region |
| PostgreSQL | pg_dump + S3 | Daily | 30 days | Different region |
| Redis | RDB snapshots | Every 6 hours | 7 days | Same region |
| File uploads | S3 cross-region replication | Continuous | Indefinite | Different region |
| Config/secrets | AWS SSM + version history | On change | All versions | Same account |

### Recovery Time Objectives
```
RTO (Recovery Time Objective):
  Database:  < 1 hour (restore from backup)
  App:       < 5 minutes (redeploy previous version)
  DNS:       < 5 minutes (TTL = 300s)

RPO (Recovery Point Objective):
  Database:  < 1 hour (point-in-time recovery)
  Files:     0 (real-time replication)
```

---

## 8 · Production Checklist

```
Infrastructure:
✓ SSL/TLS on all endpoints
✓ CDN for static assets
✓ Load balancer with health checks
✓ Auto-scaling configured
✓ Database backups automated and tested
✓ Secrets in parameter store (not env files)

Deployment:
✓ CI/CD pipeline (push → test → build → deploy)
✓ Zero-downtime deploys
✓ Rollback in < 2 minutes
✓ Database migrations run before deploy
✓ Smoke tests after deploy

Monitoring:
✓ Error tracking (Sentry)
✓ Uptime monitoring
✓ Log aggregation
✓ Performance metrics
✓ Alerting on error rate and response time

Security:
✓ Firewall rules (only necessary ports open)
✓ Non-root containers
✓ Secret rotation every 90 days
✓ Dependency vulnerability scanning
✓ DDoS protection (Cloudflare / AWS Shield)

Disaster Recovery:
✓ Backup restore tested monthly
✓ Runbooks for common incidents
✓ On-call rotation (if team > 2)
✓ Post-incident review process
```

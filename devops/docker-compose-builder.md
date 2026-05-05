# Docker Compose Builder — Claude Skill

> Build production-ready Docker configurations. Dockerfiles, multi-service compose, dev/prod parity, optimization, volumes, networking. Node.js/MERN-first.

---

## Core Directives

1. **Dev/prod parity.** Same services locally as production — only config differs.
2. **Layer efficiently.** Every Dockerfile instruction is a cache layer — order matters.
3. **Small images.** Alpine or distroless. Never ship dev dependencies.
4. **Health checks everywhere.** If it can fail, it needs a health check.

---

## 1 · Node.js Dockerfile (Production)

### Multi-Stage Build
```dockerfile
# Stage 1: Install dependencies
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts

# Stage 2: Build
FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

# Stage 3: Production
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
RUN addgroup --system --gid 1001 appgroup && \
    adduser --system --uid 1001 appuser

COPY --from=builder --chown=appuser:appgroup /app/dist ./dist
COPY --from=builder --chown=appuser:appgroup /app/node_modules ./node_modules
COPY --from=builder --chown=appuser:appgroup /app/package.json ./

USER appuser
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/healthz || exit 1

CMD ["node", "dist/index.js"]
```

### Development Dockerfile
```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
EXPOSE 3000
CMD ["npm", "run", "dev"]
```

### Dockerfile Rules
```
✓ Use specific node version tags (node:20-alpine, not node:latest)
✓ Copy package.json first, then npm ci, then source (leverage cache)
✓ Use multi-stage builds (deps → build → runtime)
✓ Run as non-root user
✓ Set NODE_ENV=production in final stage
✓ Include HEALTHCHECK instruction
✓ Use .dockerignore to exclude node_modules, .git, .env
✗ Never use npm install in production (use npm ci)
✗ Never run as root
✗ Never copy .env files into images
```

### .dockerignore
```
node_modules
.git
.env
.env.*
dist
*.md
.vscode
.github
coverage
__tests__
```

---

## 2 · Docker Compose — Local Development

### Full MERN Stack
```yaml
# docker-compose.yml
services:
  api:
    build:
      context: ./server
      dockerfile: Dockerfile.dev
    ports:
      - "3000:3000"
    volumes:
      - ./server:/app
      - /app/node_modules          # anonymous volume — don't overwrite
    environment:
      NODE_ENV: development
      MONGO_URI: mongodb://mongo:27017/myapp
      REDIS_URL: redis://redis:6379
      JWT_ACCESS_SECRET: dev-secret-change-in-prod
    depends_on:
      mongo:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped

  client:
    build:
      context: ./client
      dockerfile: Dockerfile.dev
    ports:
      - "5173:5173"
    volumes:
      - ./client:/app
      - /app/node_modules
    environment:
      VITE_API_URL: http://localhost:3000/api/v1
    depends_on:
      - api

  mongo:
    image: mongo:7
    ports:
      - "27017:27017"
    volumes:
      - mongo_data:/data/db
    healthcheck:
      test: echo 'db.runCommand("ping").ok' | mongosh --quiet
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    command: redis-server --maxmemory 256mb --maxmemory-policy allkeys-lru

  # Optional: MongoDB admin UI
  mongo-express:
    image: mongo-express
    ports:
      - "8081:8081"
    environment:
      ME_CONFIG_MONGODB_URL: mongodb://mongo:27017
    depends_on:
      - mongo
    profiles:
      - debug   # Only start with: docker compose --profile debug up

volumes:
  mongo_data:
  redis_data:
```

---

## 3 · Production Compose

```yaml
# docker-compose.prod.yml
services:
  api:
    build:
      context: ./server
      dockerfile: Dockerfile
    ports:
      - "3000:3000"
    env_file:
      - .env.production
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
        reservations:
          cpus: "0.25"
          memory: 128M
      restart_policy:
        condition: on-failure
        max_attempts: 3
    healthcheck:
      test: wget --no-verbose --tries=1 --spider http://localhost:3000/healthz || exit 1
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./client/dist:/usr/share/nginx/html:ro
      - certbot_data:/etc/letsencrypt:ro
    depends_on:
      api:
        condition: service_healthy
    restart: always

volumes:
  certbot_data:
```

### Running
```bash
# Development
docker compose up -d

# Production
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Rebuild after code changes
docker compose up --build api

# View logs
docker compose logs -f api

# Enter container shell
docker compose exec api sh
```

---

## 4 · Nginx Configuration

```nginx
# nginx/nginx.conf
events { worker_connections 1024; }

http {
  include /etc/nginx/mime.types;
  default_type application/octet-stream;

  # Gzip compression
  gzip on;
  gzip_types text/plain text/css application/json application/javascript text/xml;
  gzip_min_length 1024;

  # Rate limiting zone
  limit_req_zone $binary_remote_addr zone=api:10m rate=30r/m;

  upstream api {
    server api:3000;
  }

  server {
    listen 80;
    server_name yourdomain.com;

    # Serve React SPA
    location / {
      root /usr/share/nginx/html;
      try_files $uri $uri/ /index.html;

      # Cache static assets
      location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff2)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
      }
    }

    # Proxy API requests
    location /api/ {
      limit_req zone=api burst=10 nodelay;

      proxy_pass http://api;
      proxy_http_version 1.1;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_connect_timeout 5s;
      proxy_read_timeout 30s;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
  }
}
```

---

## 5 · Optimization Checklist

### Image Size
```bash
# Check image sizes
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

# Target sizes
# Node.js API (production): < 200MB
# Nginx + static:           < 50MB
# MongoDB:                  ~ 700MB (official)
# Redis:                    ~ 30MB (alpine)
```

### Build Optimization
```
✓ Use .dockerignore (reduce build context)
✓ Order COPY by change frequency (least → most)
✓ Combine RUN commands to reduce layers
✓ Use --no-cache for production builds
✓ Pin exact versions for reproducibility
✓ Use BuildKit: DOCKER_BUILDKIT=1 docker build .
```

### Security
```
✓ Non-root user in all containers
✓ Read-only filesystem where possible
✓ No secrets in build args or ENV (use runtime env)
✓ Scan images: docker scout cves <image>
✓ Use official base images only
✓ Keep images updated (rebuild weekly)
```

---

## 6 · Common Patterns

### Wait-for-it (Service Dependency)
```yaml
api:
  depends_on:
    mongo:
      condition: service_healthy
    redis:
      condition: service_healthy
```

### Hot Reload (Development)
```yaml
volumes:
  - ./server:/app         # Mount source code
  - /app/node_modules     # Prevent host node_modules from overriding
```

### Environment Files
```bash
# .env.development (committed, no secrets)
NODE_ENV=development
MONGO_URI=mongodb://mongo:27017/myapp-dev
REDIS_URL=redis://redis:6379

# .env.production (NOT committed, secrets via CI/CD)
NODE_ENV=production
MONGO_URI=mongodb+srv://user:pass@cluster.mongodb.net/myapp
JWT_ACCESS_SECRET=<generated-256-bit-secret>
```

### Multi-Environment Override
```bash
# Base + dev overrides
docker compose -f docker-compose.yml -f docker-compose.dev.yml up

# Base + prod overrides
docker compose -f docker-compose.yml -f docker-compose.prod.yml up
```

# Monitoring Setup — Claude Skill

> Implement production observability. Error tracking, structured logging, health checks, uptime monitoring, alerting. Node.js/Express-first.

---

## Core Directives

1. **If it's not monitored, it's not production.** Logging + error tracking from day 1.
2. **Structured logs only.** JSON, machine-parseable, with correlation IDs.
3. **Alert on symptoms, not causes.** Error rate spike > individual errors.
4. **Never log secrets.** Sanitize PII, tokens, passwords from all outputs.

---

## 1 · Structured Logging (Pino)

### Setup
```typescript
import pino from 'pino';

export const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  transport: process.env.NODE_ENV === 'development'
    ? { target: 'pino-pretty', options: { colorize: true, translateTime: 'SYS:HH:MM:ss' } }
    : undefined, // JSON in production
  redact: {
    paths: ['req.headers.authorization', 'req.headers.cookie', '*.password', '*.token', '*.secret'],
    censor: '[REDACTED]',
  },
  serializers: {
    req: pino.stdSerializers.req,
    res: pino.stdSerializers.res,
    err: pino.stdSerializers.err,
  },
});
```

### Request Logging Middleware
```typescript
import { randomUUID } from 'crypto';
import type { Request, Response, NextFunction } from 'express';

export function requestLogger(req: Request, res: Response, next: NextFunction) {
  const requestId = req.headers['x-request-id'] as string || randomUUID();
  const start = Date.now();

  // Attach to request for use in handlers
  req.requestId = requestId;
  res.setHeader('X-Request-ID', requestId);

  // Create child logger with request context
  req.log = logger.child({ requestId, method: req.method, path: req.path });

  res.on('finish', () => {
    const duration = Date.now() - start;
    const level = res.statusCode >= 500 ? 'error' : res.statusCode >= 400 ? 'warn' : 'info';

    req.log[level]({
      statusCode: res.statusCode,
      duration,
      userAgent: req.headers['user-agent'],
      ip: req.ip,
      userId: req.user?.id,
    }, `${req.method} ${req.path} ${res.statusCode} ${duration}ms`);
  });

  next();
}
```

### Log Levels Usage
| Level | When | Example |
|---|---|---|
| `fatal` | Process must exit | Uncaught exception, DB connection lost |
| `error` | Operation failed, needs attention | Payment failed, external API 500 |
| `warn` | Unexpected but recoverable | Rate limit hit, deprecated API used |
| `info` | Normal operations | Request completed, user logged in |
| `debug` | Development troubleshooting | Query results, cache hit/miss |
| `trace` | Verbose debugging | Function entry/exit, variable values |

### What to Log
```
✓ Request: method, path, status, duration, requestId
✓ Auth events: login, logout, failed attempts
✓ Business events: order placed, payment processed
✓ External API calls: service, method, duration, status
✓ Errors: message, stack, context, requestId
✓ Performance: slow queries (>100ms), slow responses (>1s)
✗ Never: passwords, tokens, credit cards, PII, full request bodies
```

---

## 2 · Error Tracking (Sentry)

### Setup
```typescript
import * as Sentry from '@sentry/node';

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV,
  release: process.env.npm_package_version,
  tracesSampleRate: process.env.NODE_ENV === 'production' ? 0.1 : 1.0,
  integrations: [
    Sentry.httpIntegration(),
    Sentry.expressIntegration(),
    Sentry.mongoIntegration(),
  ],
  beforeSend(event) {
    // Scrub sensitive data
    if (event.request?.cookies) delete event.request.cookies;
    if (event.request?.headers?.authorization) event.request.headers.authorization = '[REDACTED]';
    return event;
  },
  ignoreErrors: [
    'UNAUTHENTICATED',   // Expected auth failures
    'VALIDATION_ERROR',   // Client input errors
    'NOT_FOUND',          // 404s
  ],
});

// Express: Sentry handlers must be first/last
app.use(Sentry.expressErrorHandler());
```

### Frontend (React)
```typescript
import * as Sentry from '@sentry/react';

Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN,
  environment: import.meta.env.MODE,
  integrations: [
    Sentry.browserTracingIntegration(),
    Sentry.replayIntegration({ maskAllText: true, blockAllMedia: true }),
  ],
  tracesSampleRate: 0.1,
  replaysSessionSampleRate: 0.1,
  replaysOnErrorSampleRate: 1.0,
});

// Wrap App with ErrorBoundary
<Sentry.ErrorBoundary fallback={<ErrorFallback />}>
  <App />
</Sentry.ErrorBoundary>
```

### Source Maps Upload (CI)
```yaml
# In CI after build
- name: Upload source maps
  run: npx @sentry/cli sourcemaps upload --org=myorg --project=myapp dist/
  env:
    SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_AUTH_TOKEN }}
```

---

## 3 · Health Check Endpoints

### Implementation
```typescript
import mongoose from 'mongoose';
import { createClient } from 'redis';

// Basic health (for load balancer / Docker)
app.get('/healthz', (_req, res) => {
  res.status(200).json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Detailed readiness (for orchestrators)
app.get('/readyz', async (_req, res) => {
  const checks = {
    mongo: 'unknown',
    redis: 'unknown',
    uptime: process.uptime(),
    memory: process.memoryUsage(),
  };

  try {
    // MongoDB
    const mongoState = mongoose.connection.readyState;
    checks.mongo = mongoState === 1 ? 'connected' : 'disconnected';

    // Redis
    const pong = await redisClient.ping();
    checks.redis = pong === 'PONG' ? 'connected' : 'disconnected';

    const allHealthy = checks.mongo === 'connected' && checks.redis === 'connected';
    res.status(allHealthy ? 200 : 503).json({ status: allHealthy ? 'ok' : 'degraded', checks });
  } catch (err) {
    res.status(503).json({ status: 'unhealthy', checks, error: (err as Error).message });
  }
});
```

### Health Check Rules
```
✓ /healthz — lightweight, no DB calls (liveness probe)
✓ /readyz — checks all dependencies (readiness probe)
✓ Return 200 for healthy, 503 for unhealthy
✓ Include uptime, memory usage, dependency status
✓ Respond within 3 seconds (timeout protection)
✗ Don't include sensitive information in responses
✗ Don't run expensive operations in health checks
```

---

## 4 · Uptime Monitoring

### Tools
| Tool | Free Tier | Check Interval | Features |
|---|---|---|---|
| Betterstack (formerly Better Uptime) | 5 monitors | 3 min | Status pages, incidents |
| UptimeRobot | 50 monitors | 5 min | Basic HTTP checks |
| Checkly | 5 checks | 10 min | API + browser checks |

### What to Monitor
```
✓ Main application URL (/)
✓ API health endpoint (/healthz)
✓ API readiness endpoint (/readyz)
✓ Critical user flows (login page loads)
✓ External service status pages
✓ SSL certificate expiry (alert 30 days before)
```

### Status Page
```
✓ Create a public status page (e.g., status.yourapp.com)
✓ Show: API, Web App, Database, Email (separate components)
✓ Historical uptime percentage
✓ Incident communication channel
```

---

## 5 · Alerting Strategy

### Severity Levels
| Level | Response Time | Channel | Example |
|---|---|---|---|
| P1 Critical | Immediate | PagerDuty + SMS | App down, DB unreachable |
| P2 High | 30 min | Slack + email | Error rate >5%, response time >5s |
| P3 Medium | 4 hours | Slack | Error rate >1%, disk >80% |
| P4 Low | Next business day | Email | Deprecation warning, cert 30d |

### Alert Rules
```
✓ Alert on error RATE, not individual errors
✓ Use meaningful thresholds (not every 500 error)
✓ Include context: what, when, impact, runbook link
✓ Route to the right team (backend → backend engineers)
✓ Have escalation paths (if P1 not ack'd in 15min → escalate)
✗ Don't alert on expected errors (404s, validation errors)
✗ Don't create alert fatigue (too many low-priority alerts)
```

### Sample Alert Config
```yaml
alerts:
  - name: High Error Rate
    condition: error_rate > 5% for 5 minutes
    severity: P2
    channels: [slack-engineering, email-oncall]
    message: |
      🚨 Error rate is {{ error_rate }}% (threshold: 5%)
      Affected: {{ service }}
      Dashboard: https://grafana.example.com/d/errors
      Runbook: https://wiki.example.com/runbooks/high-error-rate

  - name: Slow Response Time
    condition: p95_response_time > 3000ms for 10 minutes
    severity: P3
    channels: [slack-engineering]

  - name: Application Down
    condition: health_check_failed for 3 consecutive checks
    severity: P1
    channels: [pagerduty, slack-engineering]
```

---

## 6 · Graceful Shutdown

```typescript
function gracefulShutdown(signal: string) {
  logger.info({ signal }, 'Received shutdown signal');

  // Stop accepting new requests
  server.close(async () => {
    logger.info('HTTP server closed');

    // Close database connections
    await mongoose.connection.close();
    logger.info('MongoDB connection closed');

    // Close Redis
    await redisClient.quit();
    logger.info('Redis connection closed');

    // Flush Sentry events
    await Sentry.close(2000);

    process.exit(0);
  });

  // Force shutdown after 30s
  setTimeout(() => {
    logger.error('Forced shutdown — connections not drained in 30s');
    process.exit(1);
  }, 30000);
}

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// Unhandled errors — log and exit
process.on('uncaughtException', (err) => {
  logger.fatal({ err }, 'Uncaught exception');
  Sentry.captureException(err);
  gracefulShutdown('uncaughtException');
});

process.on('unhandledRejection', (reason) => {
  logger.fatal({ err: reason }, 'Unhandled rejection');
  Sentry.captureException(reason);
  gracefulShutdown('unhandledRejection');
});
```

---

## 7 · Observability Checklist

### Day 1 (MVP)
```
✓ Structured logging (Pino, JSON format)
✓ Error tracking (Sentry)
✓ Health check endpoints
✓ Uptime monitoring
✓ Graceful shutdown
```

### Week 1
```
✓ Request logging with correlation IDs
✓ Error rate alerting
✓ Response time monitoring
✓ Database query logging (slow queries)
```

### Month 1
```
✓ Application metrics (Prometheus/Grafana or Datadog)
✓ Custom business metrics (signups, orders, revenue)
✓ Distributed tracing (OpenTelemetry)
✓ Log aggregation (Grafana Loki or CloudWatch)
✓ Status page for users
```

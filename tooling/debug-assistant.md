---
name: Debug Assistant
category: tooling
version: 1.0.0
description: >
  Systematically diagnose and fix bugs. Error analysis workflows, common Node.js/React/MongoDB error patterns, network debugging, memory leaks, and performance profiling.
author: Zaheer Shaik
tags:
  - debugging
  - error-handling
  - profiling
  - node
  - tooling
---

# Debug Assistant — Claude Skill

> Systematically diagnose and fix bugs. Error analysis workflows, common Node.js/React/MongoDB error patterns, network debugging, memory leaks, performance profiling.

---

## Core Directives

1. **Read the error, all of it.** Stack traces tell you exactly where and often why.
2. **Reproduce before fixing.** If you can't reproduce it, you can't verify the fix.
3. **Isolate the layer.** Is it frontend, backend, database, or network? Narrow first.
4. **Fix the root cause, not the symptom.** Catching and swallowing errors is not debugging.

---

## 1 · Error Analysis Workflow

### Step-by-Step
```
1. READ    — Full error message + stack trace. What line? What file? What type?
2. LOCATE  — Find the exact code that triggered the error.
3. REPRODUCE — Can you trigger it consistently? What input causes it?
4. ISOLATE — Is it the code, the data, the environment, or the dependency?
5. HYPOTHESIZE — What's the most likely cause? (Check the most common first)
6. FIX     — Implement the fix.
7. VERIFY  — Does the original error go away? Are there no regressions?
8. PREVENT — Add validation, test, or monitoring to prevent recurrence.
```

### Error Reading Checklist
```
□ Error type (TypeError, ReferenceError, MongoError, etc.)
□ Error message (human-readable cause)
□ Stack trace (first YOUR code line, not library internals)
□ HTTP status code (if API error)
□ Request/response details (method, path, body, headers)
□ Environment (dev/staging/prod, Node version, OS)
□ Timing (always, intermittent, after deploy, at certain times)
```

---

## 2 · Common Node.js Errors

### TypeError
```
TypeError: Cannot read properties of undefined (reading 'xxx')

Cause: Accessing property on null/undefined value
Debug:
1. Find the variable that's undefined
2. Trace where it should be set
3. Check: missing await? Wrong destructuring? Missing null check?

Fix pattern:
// Before: user.profile.name  (user or profile could be undefined)
// After:  user?.profile?.name  (optional chaining)
// Better: validate that user exists before accessing nested props
```

### UnhandledPromiseRejection
```
UnhandledPromiseRejectionWarning: ...

Cause: async function threw without try/catch, or .then() without .catch()
Debug:
1. Find the async operation in the stack trace
2. Wrap in try/catch or add .catch()
3. Check: are all async route handlers wrapped?

Fix: Use async error wrapper for Express
const asyncHandler = (fn) => (req, res, next) => fn(req, res, next).catch(next);
router.get('/users', asyncHandler(async (req, res) => { ... }));
```

### ECONNREFUSED
```
Error: connect ECONNREFUSED 127.0.0.1:27017

Cause: Cannot connect to service (MongoDB, Redis, etc.)
Debug:
1. Is the service running? (docker ps, systemctl status mongod)
2. Is the port correct? (check env vars)
3. Is it a Docker networking issue? (use service name, not localhost)
4. Firewall blocking?

Fix:
- Docker: use service name (mongo:27017) not localhost
- Check MONGO_URI in .env matches running instance
- Verify with: mongosh "mongodb://localhost:27017"
```

### EADDRINUSE
```
Error: listen EADDRINUSE: address already in use :::3000

Cause: Port already occupied by another process
Fix:
# Find and kill process
lsof -i :3000
kill -9 <PID>

# Or use a different port
PORT=3001 npm run dev
```

### MODULE_NOT_FOUND
```
Error: Cannot find module './config/env'

Cause: Import path doesn't match file location
Debug:
1. Does the file exist at that path?
2. Is the extension correct? (.ts vs .js vs .tsx)
3. Is the alias configured? (tsconfig paths, vite alias)
4. Did you npm install after adding a dependency?
```

---

## 3 · Common React Errors

### Hydration Mismatch (Next.js / SSR)
```
Error: Hydration failed because the initial UI does not match what was rendered on the server

Cause: Server-rendered HTML differs from client render
Common causes:
- Using Date.now(), Math.random() in render
- Browser-only APIs (window, localStorage) in initial render
- Different data between server and client
- Invalid HTML nesting (<div> inside <p>)

Fix:
// Use useEffect for client-only values
const [time, setTime] = useState<string>('');
useEffect(() => setTime(new Date().toLocaleString()), []);
```

### Hooks Rules Violation
```
Error: React Hook "useXxx" is called conditionally

Cause: Hook called inside if/loop/nested function
Fix: Hooks must be called at top level of component, every render
// BAD: if (condition) { useState(...) }
// GOOD: const [val, setVal] = useState(condition ? x : y);
```

### Infinite Re-render
```
Error: Maximum update depth exceeded

Cause: setState called during render (not in event handler or effect)
Common patterns:
// BAD: setState in render body
function Component() {
  const [count, setCount] = useState(0);
  setCount(count + 1);  // Infinite loop!
}

// BAD: useEffect with missing/wrong deps
useEffect(() => {
  setData(transform(data));  // data changes → effect runs → data changes → ...
}, [data]);

// FIX: useMemo for derived state
const transformed = useMemo(() => transform(data), [data]);
```

### Memory Leak Warning
```
Warning: Can't perform a React state update on an unmounted component

Cause: Async operation completes after component unmounts
Fix:
useEffect(() => {
  const controller = new AbortController();
  fetch('/api/data', { signal: controller.signal })
    .then(res => res.json())
    .then(setData)
    .catch(err => { if (err.name !== 'AbortError') throw err; });
  return () => controller.abort();
}, []);
```

---

## 4 · MongoDB/Mongoose Errors

### CastError
```
CastError: Cast to ObjectId failed for value "undefined"

Cause: Invalid ObjectId passed to query
Debug: Check that the ID parameter is defined and correctly formatted
Fix:
// Validate before querying
if (!mongoose.Types.ObjectId.isValid(id)) throw new AppError(400, 'INVALID_ID', 'Invalid ID format');
```

### ValidationError
```
ValidationError: User validation failed: email: Path `email` is required

Cause: Required field missing in document
Debug: Check the data being saved — log it before save()
Fix: Validate input with Zod BEFORE Mongoose, give better error messages
```

### Duplicate Key
```
MongoServerError: E11000 duplicate key error collection: myapp.users index: email_1

Cause: Unique constraint violation
Fix:
try { await User.create(data); }
catch (err) {
  if (err.code === 11000) throw new AppError(409, 'DUPLICATE', 'Email already exists');
  throw err;
}
```

### Connection Issues
```
MongooseServerSelectionError: Could not connect to any servers

Debug checklist:
1. Is MONGO_URI correct? (check for typos, special chars in password)
2. Is MongoDB running? (mongosh to verify)
3. Is the network reachable? (VPN, firewall, IP whitelist on Atlas)
4. DNS resolution working? (nslookup cluster.mongodb.net)
5. Connection string URL-encoded? (special chars in password: encodeURIComponent())
```

---

## 5 · Network Debugging

### CORS Errors
```
Access-Control-Allow-Origin header missing

Debug:
1. Is CORS middleware configured? (cors({ origin: ... }))
2. Is the origin in the whitelist?
3. Credentials included? (credentials: 'include' + cors({ credentials: true }))
4. Is it a preflight (OPTIONS) request that's blocked?

Fix: Explicit CORS config
app.use(cors({
  origin: ['http://localhost:5173', 'https://myapp.com'],
  credentials: true,
  methods: ['GET', 'POST', 'PATCH', 'DELETE'],
}));
```

### SSL/TLS Errors
```
Error: unable to verify the first certificate

Cause: Self-signed cert, expired cert, or incomplete chain
Debug: openssl s_client -connect hostname:443 -servername hostname
Fix: Don't disable verification in production! Fix the certificate chain.
```

### Timeout Debugging
```
Order of investigation:
1. DNS resolution: nslookup / dig hostname
2. TCP connection: telnet hostname port
3. TLS handshake: openssl s_client
4. HTTP response: curl -v -o /dev/null URL
5. Application logic: check server logs for processing time
```

---

## 6 · Memory Leak Detection

### Node.js Memory Monitoring
```typescript
// Log memory usage periodically
setInterval(() => {
  const usage = process.memoryUsage();
  logger.debug({
    heapUsed: `${Math.round(usage.heapUsed / 1024 / 1024)}MB`,
    heapTotal: `${Math.round(usage.heapTotal / 1024 / 1024)}MB`,
    rss: `${Math.round(usage.rss / 1024 / 1024)}MB`,
    external: `${Math.round(usage.external / 1024 / 1024)}MB`,
  }, 'Memory usage');
}, 60000);
```

### Common Leak Sources
| Source | Symptom | Fix |
|---|---|---|
| Event listener not removed | Growing listener count | Remove in cleanup/destroy |
| Global cache without eviction | Growing heap | Set maxSize, use LRU |
| Unclosed database connections | Growing connection pool | Close on error, use pool |
| Large closures in loops | Growing heap | Break reference after use |
| Uncleared intervals/timeouts | Never GC'd | Clear on shutdown |

### Heap Snapshot
```bash
# Take heap snapshot from running process
kill -USR2 <PID>    # If --heapsnapshot-signal=SIGUSR2 flag set

# Or programmatically
node --inspect app.js
# Open Chrome DevTools → Memory → Take Heap Snapshot
```

---

## 7 · Performance Debugging

### Slow API Response
```
Investigation order:
1. Is it the database? → Log query times
2. Is it an external API? → Log external call durations
3. Is it computation? → Profile with --prof
4. Is it network? → Check response size, compression

// Quick timing instrumentation
const start = performance.now();
const result = await db.query(...);
const duration = performance.now() - start;
if (duration > 100) logger.warn({ duration, query: '...' }, 'Slow query');
```

### MongoDB Slow Queries
```javascript
// Enable profiling (development only)
db.setProfilingLevel(1, { slowms: 100 });

// View slow queries
db.system.profile.find().sort({ ts: -1 }).limit(10);

// Check if index is used
db.posts.find({ status: 'published' }).explain('executionStats');
// COLLSCAN = full scan (bad) → add index
// IXSCAN = index scan (good)
```

### Event Loop Blocking
```typescript
// Detect blocked event loop
import blocked from 'blocked-at';

blocked((time, stack) => {
  logger.warn({ time, stack }, `Event loop blocked for ${time}ms`);
}, { threshold: 100 }); // Alert if blocked > 100ms
```

---

## 8 · Debug Checklist by Symptom

| Symptom | Check First | Check Second | Check Third |
|---|---|---|---|
| 500 error | Server logs | Error handler | Database connection |
| 404 error | Route registration | URL path | Method (GET vs POST) |
| 401 error | Token present? | Token expired? | Secret mismatch? |
| 403 error | User role/permissions | Resource ownership | CORS |
| Slow response | Database queries | External APIs | Response size |
| Crash on start | Missing env vars | Port in use | Syntax error |
| Works locally, fails in prod | Env vars different | Node version | Missing build step |
| Intermittent errors | Race conditions | Memory leaks | Connection pool exhaustion |

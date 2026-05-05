# API Design — Claude Skill

> Design and implement production-grade APIs. REST, GraphQL, tRPC conventions. Versioning, pagination, error handling, documentation. MERN-first.

---

## Core Directives

1. **APIs are contracts.** Breaking changes require versioning and migration paths.
2. **Consistent over clever.** Same patterns everywhere — predictable is maintainable.
3. **Validate at the boundary.** Trust nothing from the client. Parse, don't assume.
4. **Document by default.** If it's not documented, it doesn't exist.

---

## 1 · REST API Conventions

### URL Structure
```
GET    /api/v1/resources          → list (paginated)
GET    /api/v1/resources/:id      → detail
POST   /api/v1/resources          → create (201)
PATCH  /api/v1/resources/:id      → partial update
DELETE /api/v1/resources/:id      → soft-delete (default)
PUT    /api/v1/resources/:id      → full replace (rare)

Nested resources (max 2 levels):
GET    /api/v1/posts/:postId/comments
POST   /api/v1/posts/:postId/comments
```

### Naming Rules
```
✓ Plural nouns: /users, /posts, /comments
✓ Kebab-case: /user-profiles, /order-items
✗ No verbs: /getUsers, /createPost
✗ No trailing slashes: /users/
✗ No file extensions: /users.json
```

### Status Codes (Use Correctly)
| Code | When |
|---|---|
| 200 | Success (GET, PATCH, DELETE) |
| 201 | Created (POST) |
| 204 | No content (DELETE with no body) |
| 400 | Validation error, malformed request |
| 401 | Unauthenticated (no/invalid token) |
| 403 | Forbidden (authenticated but not authorized) |
| 404 | Resource not found |
| 409 | Conflict (duplicate, state conflict) |
| 422 | Unprocessable entity (valid JSON, invalid semantics) |
| 429 | Rate limited |
| 500 | Server error (never expose internals) |

### Response Envelope
```typescript
// Success
{
  "data": { ... },
  "meta": { "page": 1, "limit": 20, "total": 150, "totalPages": 8 }
}

// Error
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Human-readable summary",
    "details": [{ "field": "email", "issue": "Invalid format" }]
  }
}

// No wrapping for single-resource GET:
{ "data": { "id": "...", "name": "..." } }
```

---

## 2 · Pagination, Filtering, Sorting

### Pagination (Offset-based Default)
```
GET /api/v1/posts?page=2&limit=20

Response meta:
{ "page": 2, "limit": 20, "total": 150, "totalPages": 8 }
```

### Cursor-based (For Real-time/Infinite Scroll)
```
GET /api/v1/posts?cursor=eyJpZCI6MTIzfQ&limit=20

Response meta:
{ "nextCursor": "eyJpZCI6MTQzfQ", "hasMore": true }
```

### When to Use Which
| Pattern | Use Case |
|---|---|
| Offset | Admin panels, tables with page numbers |
| Cursor | Feeds, infinite scroll, real-time data |

### Filtering & Sorting
```
GET /api/v1/posts?status=published&author=userId&sort=-createdAt,title

Query parser:
const { page = 1, limit = 20, sort = '-createdAt', ...filters } = req.query;

// Cap limit
const safeLimit = Math.min(Number(limit), 100);

// Parse sort: "-createdAt" → { createdAt: -1 }
const sortObj = sort.split(',').reduce((acc, field) => {
  const dir = field.startsWith('-') ? -1 : 1;
  acc[field.replace(/^-/, '')] = dir;
  return acc;
}, {});
```

### Query Builder Pattern (MongoDB)
```typescript
export function buildQuery(filters: Record<string, any>) {
  const query: Record<string, any> = {};

  if (filters.status) query.status = filters.status;
  if (filters.search) query.$text = { $search: filters.search };
  if (filters.startDate || filters.endDate) {
    query.createdAt = {};
    if (filters.startDate) query.createdAt.$gte = new Date(filters.startDate);
    if (filters.endDate) query.createdAt.$lte = new Date(filters.endDate);
  }

  return query;
}
```

---

## 3 · Input Validation Layer

### Zod Schema Pattern
```typescript
import { z } from 'zod';

// Reusable primitives
const objectId = z.string().regex(/^[a-f\d]{24}$/i, 'Invalid ID');
const pagination = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

// Resource DTO
export const CreatePostDto = z.object({
  title: z.string().trim().min(1).max(200),
  content: z.string().trim().min(1).max(50000),
  tags: z.array(z.string().trim().max(50)).max(10).default([]),
  status: z.enum(['draft', 'published']).default('draft'),
});

export const UpdatePostDto = CreatePostDto.partial();
export const PostParamsDto = z.object({ id: objectId });

// Validation middleware
export function validate(schema: z.ZodSchema, source: 'body' | 'query' | 'params' = 'body') {
  return (req: Request, _res: Response, next: NextFunction) => {
    const result = schema.safeParse(req[source]);
    if (!result.success) {
      const details = result.error.issues.map((i) => ({
        field: i.path.join('.'),
        issue: i.message,
      }));
      throw new AppError(400, 'VALIDATION_ERROR', 'Invalid input', details);
    }
    req[source] = result.data;
    next();
  };
}

// Usage: router.post('/', validate(CreatePostDto), createPost);
```

---

## 4 · GraphQL Patterns

### When GraphQL Over REST
| Use GraphQL | Stick with REST |
|---|---|
| Multiple clients need different shapes | Single client, stable shapes |
| Deep relational data (social, CMS) | Simple CRUD |
| Rapid frontend iteration | Public API for third parties |
| Avoiding over/under-fetching matters | Caching simplicity matters |

### Schema-First Setup (Apollo Server + Express)
```typescript
const typeDefs = gql`
  type Post {
    id: ID!
    title: String!
    author: User!
    comments(limit: Int = 10): [Comment!]!
    createdAt: DateTime!
  }

  type Query {
    posts(page: Int, limit: Int, filter: PostFilter): PostConnection!
    post(id: ID!): Post
  }

  type Mutation {
    createPost(input: CreatePostInput!): Post!
    updatePost(id: ID!, input: UpdatePostInput!): Post!
    deletePost(id: ID!): Boolean!
  }

  input PostFilter { status: PostStatus, authorId: ID }
  input CreatePostInput { title: String!, content: String!, tags: [String!] }
`;
```

### N+1 Prevention (DataLoader)
```typescript
import DataLoader from 'dataloader';

// Create per-request DataLoader
export function createLoaders() {
  return {
    userById: new DataLoader(async (ids: readonly string[]) => {
      const users = await User.find({ _id: { $in: ids } });
      const map = new Map(users.map((u) => [u.id, u]));
      return ids.map((id) => map.get(id) || null);
    }),
  };
}

// In resolver: post.author → context.loaders.userById.load(post.authorId)
```

### GraphQL Security
```
✓ Query depth limiting (max 5-7 levels)
✓ Query complexity analysis (cost per field)
✓ Disable introspection in production
✓ Persisted queries for known operations
✓ Rate limit by operation complexity, not just request count
```

---

## 5 · tRPC (End-to-End Type Safety)

### When to Use
- Fullstack TypeScript monorepo (Next.js, T3 stack)
- Team controls both client and server
- Type safety is top priority

### Setup Pattern
```typescript
// server/trpc.ts
import { initTRPC, TRPCError } from '@trpc/server';

const t = initTRPC.context<Context>().create();

export const router = t.router;
export const publicProcedure = t.procedure;
export const protectedProcedure = t.procedure.use(async ({ ctx, next }) => {
  if (!ctx.user) throw new TRPCError({ code: 'UNAUTHORIZED' });
  return next({ ctx: { user: ctx.user } });
});

// server/routers/post.ts
export const postRouter = router({
  list: publicProcedure
    .input(z.object({ page: z.number().default(1), limit: z.number().max(100).default(20) }))
    .query(async ({ input }) => {
      return postService.findAll(input);
    }),

  create: protectedProcedure
    .input(CreatePostDto)
    .mutation(async ({ input, ctx }) => {
      return postService.create({ ...input, authorId: ctx.user.id });
    }),
});
```

---

## 6 · API Documentation

### OpenAPI / Swagger (Express)
```typescript
import swaggerJsdoc from 'swagger-jsdoc';
import swaggerUi from 'swagger-ui-express';

const spec = swaggerJsdoc({
  definition: {
    openapi: '3.0.0',
    info: { title: 'API', version: '1.0.0' },
    servers: [{ url: '/api/v1' }],
    components: {
      securitySchemes: {
        bearerAuth: { type: 'http', scheme: 'bearer', bearerFormat: 'JWT' },
      },
    },
  },
  apis: ['./src/modules/**/routes.ts'],
});

app.use('/docs', swaggerUi.serve, swaggerUi.setup(spec));
```

### Documentation Checklist
```
✓ Every endpoint has summary + description
✓ Request body schemas with examples
✓ Response schemas for success AND error cases
✓ Authentication requirements marked
✓ Rate limit headers documented
✓ Pagination parameters documented
```

---

## 7 · Versioning Strategy

| Strategy | Pros | Cons | Use When |
|---|---|---|---|
| URL `/v1/` | Simple, explicit | URL pollution | Public APIs, breaking changes |
| Header `Accept: v=2` | Clean URLs | Hidden, harder to test | Internal APIs |
| No versioning | Simple | Breaking changes break clients | Early stage, single client |

### Default: URL Versioning
```typescript
// Mount versioned routers
app.use('/api/v1', v1Router);
app.use('/api/v2', v2Router); // only when needed

// Migration: keep v1 alive with deprecation headers
app.use('/api/v1', (req, res, next) => {
  res.setHeader('Deprecation', 'true');
  res.setHeader('Sunset', 'Wed, 01 Jan 2025 00:00:00 GMT');
  next();
}, v1Router);
```

---

## 8 · Rate Limiting

### Per-Endpoint Strategy
| Tier | Limit | Window | Key |
|---|---|---|---|
| Public / anonymous | 30 req | 1 min | IP |
| Authenticated | 120 req | 1 min | User ID |
| Auth endpoints | 5 req | 15 min | IP + email |
| File upload | 10 req | 1 hour | User ID |
| Webhook receivers | 100 req | 1 min | Source IP |

### Implementation
```typescript
import rateLimit from 'express-rate-limit';
import RedisStore from 'rate-limit-redis';

const apiLimiter = rateLimit({
  windowMs: 60_000,
  max: 120,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => req.user?.id || req.ip,
  store: new RedisStore({ sendCommand: (...args) => redisClient.sendCommand(args) }),
});

const authLimiter = rateLimit({ windowMs: 15 * 60_000, max: 5 });

app.use('/api', apiLimiter);
app.use('/api/auth/login', authLimiter);
```

### Rate Limit Headers
```
RateLimit-Limit: 120
RateLimit-Remaining: 87
RateLimit-Reset: 1620000000
Retry-After: 30  (only on 429)
```

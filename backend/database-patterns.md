---
name: Database Patterns
category: backend
version: 1.0.0
description: >
  Design and implement database schemas, queries, and access patterns. MongoDB, PostgreSQL, indexing, migrations, connection pooling, and data modeling.
author: Zaheer Shaik
tags:
  - database
  - mongodb
  - postgresql
  - data-modeling
  - backend
---

# Database Patterns — Claude Skill

> Design, optimize, and maintain production databases. Schema design, migrations, indexing, query optimization. MongoDB-first with PostgreSQL patterns.

---

## Core Directives

1. **Schema is destiny.** A bad schema can't be fixed with code — design it right.
2. **Index what you query.** Every slow query is a missing index until proven otherwise.
3. **Migrations are code.** Version them, review them, test them, make them reversible.
4. **Measure, don't guess.** Use EXPLAIN, profile queries, monitor slow query logs.

---

## 1 · MongoDB Schema Design

### Embedding vs Referencing
| Embed (subdocument) | Reference (ObjectId) |
|---|---|
| Data always read together | Data accessed independently |
| 1:few relationship | 1:many or many:many |
| Bounded growth (≤100 items) | Unbounded growth |
| Atomic updates needed | Independent lifecycle |

### Schema Template
```typescript
import { Schema, model, Types } from 'mongoose';

const postSchema = new Schema(
  {
    title: { type: String, required: true, maxlength: 200, trim: true, index: true },
    slug: { type: String, required: true, unique: true, lowercase: true },
    content: { type: String, required: true, maxlength: 50000 },
    status: { type: String, enum: ['draft', 'published', 'archived'], default: 'draft', index: true },
    author: { type: Types.ObjectId, ref: 'User', required: true, index: true },

    // Embed: bounded, always read together
    tags: { type: [String], default: [], validate: [v => v.length <= 10, 'Max 10 tags'] },
    metadata: {
      readTime: Number,
      wordCount: Number,
      views: { type: Number, default: 0 },
    },

    // Soft delete
    deletedAt: { type: Date, default: null, index: true },
  },
  {
    timestamps: true,
    toJSON: { virtuals: true, transform: (_doc, ret) => { delete ret.__v; return ret; } },
  },
);

// Compound indexes for common queries
postSchema.index({ status: 1, createdAt: -1 });
postSchema.index({ author: 1, status: 1 });
postSchema.index({ title: 'text', content: 'text' }); // full-text search

// Query middleware: exclude soft-deleted by default
postSchema.pre(/^find/, function () { this.where({ deletedAt: null }); });

export const Post = model('Post', postSchema);
```

### Anti-Patterns
```
✗ Unbounded arrays (comments inside post — use separate collection)
✗ Deep nesting (>2 levels — flatten or reference)
✗ Storing derived data without invalidation strategy
✗ Using ObjectId strings instead of Types.ObjectId
✗ Missing indexes on fields used in queries
✗ Storing large blobs in documents (use GridFS or S3)
```

---

## 2 · PostgreSQL Schema Design

### Schema Template
```sql
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE users (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email       VARCHAR(255) NOT NULL UNIQUE,
  password    VARCHAR(255) NOT NULL,
  role        VARCHAR(20) NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin', 'moderator')),
  is_verified BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at  TIMESTAMPTZ
);

CREATE TABLE posts (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title      VARCHAR(200) NOT NULL,
  slug       VARCHAR(250) NOT NULL UNIQUE,
  content    TEXT NOT NULL,
  status     VARCHAR(20) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'archived')),
  author_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  tags       TEXT[] DEFAULT '{}',
  metadata   JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

-- Indexes
CREATE INDEX idx_posts_status_created ON posts(status, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_posts_author ON posts(author_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_posts_slug ON posts(slug);
CREATE INDEX idx_posts_tags ON posts USING GIN(tags);
CREATE INDEX idx_posts_search ON posts USING GIN(to_tsvector('english', title || ' ' || content));

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END; $$ LANGUAGE plpgsql;
CREATE TRIGGER posts_updated BEFORE UPDATE ON posts FOR EACH ROW EXECUTE FUNCTION update_timestamp();
```

### PostgreSQL vs MongoDB Decision
| PostgreSQL | MongoDB |
|---|---|
| Relational data with joins | Document-heavy, flexible schema |
| ACID transactions required | Eventual consistency acceptable |
| Complex queries (aggregations, CTEs) | Simple read-heavy patterns |
| Strong data integrity (FK, constraints) | Rapid prototyping, unknown schema |
| Geospatial with PostGIS | Built-in geo queries |

---

## 3 · Indexing Strategy

### Index Types
| Type | Use Case | Example |
|---|---|---|
| Single field | Direct lookups | `{ email: 1 }` |
| Compound | Multi-field queries | `{ status: 1, createdAt: -1 }` |
| Text | Full-text search | `{ title: 'text', content: 'text' }` |
| Partial (Mongo) / Filtered (PG) | Subset of docs | `{ status: 1 }, { partialFilterExpression: { deletedAt: null } }` |
| TTL | Auto-expire docs | `{ expiresAt: 1 }, { expireAfterSeconds: 0 }` |
| Unique | Prevent duplicates | `{ slug: 1 }, { unique: true }` |

### Index Rules
```
✓ Index every field in WHERE/filter clauses
✓ Index every field used in sort operations
✓ Index foreign keys (MongoDB doesn't auto-index references)
✓ Use compound indexes for queries with multiple conditions
✓ Put high-cardinality fields first in compound indexes
✓ Use partial indexes to exclude soft-deleted records
✗ Don't index fields rarely queried
✗ Don't over-index — each index costs write performance
✗ Don't create redundant indexes (compound {a,b} covers queries on {a})
```

### Analyzing Queries
```javascript
// MongoDB — check if index is used
db.posts.find({ status: 'published' }).sort({ createdAt: -1 }).explain('executionStats');
// Look for: IXSCAN (good) vs COLLSCAN (bad)

// PostgreSQL
EXPLAIN ANALYZE SELECT * FROM posts WHERE status = 'published' ORDER BY created_at DESC;
// Look for: Index Scan (good) vs Seq Scan (bad)
```

---

## 4 · Migration Patterns

### Tool Selection
| Stack | Tool | Notes |
|---|---|---|
| MongoDB + Mongoose | migrate-mongo | JS-based, up/down |
| PostgreSQL + Drizzle | drizzle-kit | Auto-generated from schema |
| PostgreSQL + Prisma | prisma migrate | Schema-driven |
| Raw SQL | node-pg-migrate | SQL files, version tracked |

### Migration Rules
```
✓ Every migration has an up AND down
✓ Migrations are immutable once deployed (never edit, create new)
✓ Additive-only when possible (add column → backfill → drop old)
✓ Test migrations on production-size data before deploying
✓ Run in transactions where possible (PostgreSQL)
✓ Separate data migrations from schema migrations
✗ Never drop columns/tables without verifying no code references them
✗ Never rename columns in one step (add new → copy → drop old)
```

### Zero-Downtime Migration (Column Rename)
```
Step 1: Add new column (nullable)
Step 2: Deploy code that writes to BOTH columns
Step 3: Backfill old rows: UPDATE posts SET new_col = old_col WHERE new_col IS NULL
Step 4: Deploy code that reads from new column only
Step 5: Add NOT NULL constraint to new column
Step 6: Drop old column
```

### migrate-mongo Template
```javascript
module.exports = {
  async up(db) {
    await db.collection('posts').updateMany(
      { status: { $exists: false } },
      { $set: { status: 'draft' } },
    );
    await db.collection('posts').createIndex({ status: 1, createdAt: -1 });
  },

  async down(db) {
    await db.collection('posts').dropIndex('status_1_createdAt_-1');
    await db.collection('posts').updateMany({}, { $unset: { status: '' } });
  },
};
```

---

## 5 · Query Optimization

### N+1 Prevention
```typescript
// BAD: N+1 — 1 query for posts + N queries for authors
const posts = await Post.find();
for (const post of posts) {
  post.author = await User.findById(post.author); // N queries!
}

// GOOD: Eager loading with populate
const posts = await Post.find().populate('author', 'name email avatar');

// GOOD: Manual batch loading
const posts = await Post.find();
const authorIds = [...new Set(posts.map(p => p.author.toString()))];
const authors = await User.find({ _id: { $in: authorIds } });
const authorMap = new Map(authors.map(a => [a.id, a]));
posts.forEach(p => p.authorData = authorMap.get(p.author.toString()));
```

### Projection (Select Only What You Need)
```typescript
// BAD
const user = await User.findById(id); // fetches ALL fields

// GOOD
const user = await User.findById(id).select('name email avatar');

// PostgreSQL equivalent
SELECT name, email, avatar FROM users WHERE id = $1;
```

### Connection Pooling
```typescript
// MongoDB (Mongoose default pool: 100)
mongoose.connect(MONGO_URI, {
  maxPoolSize: 20,       // adjust per server
  minPoolSize: 5,
  maxIdleTimeMS: 30000,
  serverSelectionTimeoutMS: 5000,
  socketTimeoutMS: 45000,
});

// PostgreSQL (pg Pool)
const pool = new Pool({
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});
```

### Aggregation Pipeline (MongoDB)
```typescript
const stats = await Post.aggregate([
  { $match: { status: 'published', deletedAt: null } },
  { $group: {
      _id: '$author',
      postCount: { $sum: 1 },
      totalViews: { $sum: '$metadata.views' },
      avgReadTime: { $avg: '$metadata.readTime' },
  }},
  { $sort: { totalViews: -1 } },
  { $limit: 10 },
  { $lookup: {
      from: 'users', localField: '_id', foreignField: '_id', as: 'author',
      pipeline: [{ $project: { name: 1, avatar: 1 } }],
  }},
  { $unwind: '$author' },
]);
```

---

## 6 · Backup & Recovery

### Strategy
| Tier | Method | Frequency | Retention |
|---|---|---|---|
| Development | Manual dumps | On demand | 7 days |
| Staging | Automated snapshots | Daily | 14 days |
| Production | Continuous (oplog/WAL) + snapshots | Continuous + daily | 30+ days |

### MongoDB Backup
```bash
# Full dump
mongodump --uri="$MONGO_URI" --gzip --archive=backup-$(date +%F).gz

# Restore
mongorestore --uri="$MONGO_URI" --gzip --archive=backup-2024-01-15.gz --drop

# Atlas: automatic daily snapshots + point-in-time recovery
```

### PostgreSQL Backup
```bash
# Logical backup
pg_dump -Fc --no-owner $DATABASE_URL > backup-$(date +%F).dump

# Restore
pg_restore --no-owner -d $DATABASE_URL backup-2024-01-15.dump

# Continuous: WAL archiving + pg_basebackup for PITR
```

### Backup Checklist
```
✓ Automate backups (cron or managed service)
✓ Test restores monthly (untested backups aren't backups)
✓ Store backups in different region than primary
✓ Encrypt backups at rest
✓ Monitor backup job success/failure
✓ Document restore procedure (runbook)
```

---

## 7 · Data Modeling Patterns

### Soft Delete
```typescript
// Add to every model that needs it
deletedAt: { type: Date, default: null, index: true }

// Query middleware
schema.pre(/^find/, function() { this.where({ deletedAt: null }); });

// Soft delete method
schema.methods.softDelete = function() { return this.updateOne({ deletedAt: new Date() }); };

// To query including deleted: Model.findWithDeleted() or Model.find().setOptions({ includeDeleted: true });
```

### Audit Trail
```typescript
const auditSchema = new Schema({
  entityType: { type: String, required: true, index: true },
  entityId: { type: Types.ObjectId, required: true, index: true },
  action: { type: String, enum: ['create', 'update', 'delete'], required: true },
  changes: Schema.Types.Mixed, // { field: { from: old, to: new } }
  performedBy: { type: Types.ObjectId, ref: 'User', required: true },
  performedAt: { type: Date, default: Date.now, index: true },
});
```

### Slug Generation
```typescript
import slugify from 'slugify';

schema.pre('save', async function () {
  if (!this.isModified('title')) return;
  let slug = slugify(this.title, { lower: true, strict: true });
  const existing = await this.constructor.countDocuments({ slug, _id: { $ne: this._id } });
  if (existing) slug = `${slug}-${Date.now().toString(36)}`;
  this.slug = slug;
});
```

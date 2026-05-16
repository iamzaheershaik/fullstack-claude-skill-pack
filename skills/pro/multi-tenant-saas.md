---
name: Multi-Tenant SaaS
category: pro
version: 1.0.0
description: >
  Build multi-tenant applications. Tenant isolation, per-tenant billing, subdomain routing, data segregation, and white-labeling. MongoDB + Express.
author: Zaheer Shaik
tags:
  - multi-tenant
  - saas
  - tenant-isolation
  - billing
  - pro
---

# Multi-Tenant SaaS — Claude Skill (Pro)

> Build multi-tenant applications. Tenant isolation, per-tenant billing, subdomain routing, data segregation, white-labeling. MongoDB + Express.

---

## Core Directives

1. **Isolate by default.** Every query must be scoped to the tenant — no exceptions.
2. **One codebase, many tenants.** Never fork code per customer.
3. **Plan for 1000 tenants.** Design decisions at 1 tenant break at 1000.
4. **Audit everything.** Who did what, in which tenant, when.

---

## 1 · Tenancy Strategies

### Decision Matrix
| Strategy | Isolation | Cost | Complexity | Use When |
|---|---|---|---|---|
| **Shared DB, shared schema** | Low | Lowest | Low | Most SaaS, <1000 tenants |
| **Shared DB, separate schema** | Medium | Low | Medium | Compliance needs |
| **Separate DB per tenant** | Highest | Highest | High | Enterprise, regulated data |

### Default: Shared DB, Shared Schema (orgId scoping)
```typescript
// Every tenant-scoped model has orgId
const projectSchema = new Schema({
  org: { type: Types.ObjectId, ref: 'Org', required: true, index: true },
  name: { type: String, required: true },
  // ... other fields
});

// Compound indexes include org
projectSchema.index({ org: 1, name: 1 });
projectSchema.index({ org: 1, createdAt: -1 });
```

---

## 2 · Tenant Scoping Middleware

### Auto-Scope All Queries
```typescript
// Middleware: attach org to request
export async function tenantScope(req: Request, _res: Response, next: NextFunction) {
  const orgId = req.headers['x-org-id'] as string;
  if (!orgId) throw new AppError(400, 'MISSING_TENANT', 'X-Org-Id header required');

  const membership = await Membership.findOne({ user: req.user.id, org: orgId });
  if (!membership) throw new AppError(403, 'NOT_MEMBER', 'Access denied');

  req.org = await Org.findById(orgId);
  req.membership = membership;
  req.tenantFilter = { org: orgId }; // use in all queries
  next();
}

// Usage in controllers — ALWAYS include tenantFilter
export async function listProjects(req: Request, res: Response) {
  const projects = await Project.find({ ...req.tenantFilter, ...buildFilters(req.query) })
    .sort({ createdAt: -1 })
    .limit(20);
  res.json({ data: projects });
}

// DANGEROUS without scoping:
// await Project.find({})  ← leaks ALL tenants' data!
// SAFE:
// await Project.find({ org: req.org.id })  ← scoped
```

### Mongoose Plugin (Auto-Scope)
```typescript
export function tenantPlugin(schema: Schema) {
  schema.add({ org: { type: Types.ObjectId, ref: 'Org', required: true, index: true } });

  // Auto-filter on find queries
  schema.pre(/^find/, function () {
    if (!this.getOptions().skipTenantScope) {
      const orgId = this.getOptions().orgId;
      if (orgId) this.where({ org: orgId });
    }
  });
}

// Apply to all tenant-scoped models
projectSchema.plugin(tenantPlugin);
taskSchema.plugin(tenantPlugin);
```

---

## 3 · Subdomain Routing

### Express Subdomain Detection
```typescript
export function subdomainResolver(req: Request, _res: Response, next: NextFunction) {
  const host = req.hostname; // acme.yourapp.com
  const parts = host.split('.');

  // Skip: yourapp.com, www.yourapp.com, api.yourapp.com
  const reserved = ['www', 'api', 'app', 'admin', 'staging'];

  if (parts.length >= 3 && !reserved.includes(parts[0])) {
    req.tenantSlug = parts[0]; // "acme"
  }

  next();
}

// Resolve slug to org
export async function resolveSubdomain(req: Request, _res: Response, next: NextFunction) {
  if (!req.tenantSlug) return next();

  const org = await Org.findOne({ slug: req.tenantSlug });
  if (!org) throw new AppError(404, 'TENANT_NOT_FOUND', 'Organization not found');

  req.org = org;
  req.tenantFilter = { org: org.id };
  next();
}

// Nginx config for wildcard subdomains
// server_name *.yourapp.com;
```

### Custom Domains
```typescript
const orgSchema = new Schema({
  slug: { type: String, unique: true },
  customDomain: { type: String, unique: true, sparse: true },
  // ...
});

// Resolve by custom domain OR subdomain
export async function resolveTenant(req: Request, _res: Response, next: NextFunction) {
  const host = req.hostname;

  let org = await Org.findOne({ customDomain: host });
  if (!org) {
    const slug = host.split('.')[0];
    org = await Org.findOne({ slug });
  }
  if (!org) throw new AppError(404, 'TENANT_NOT_FOUND', 'Organization not found');

  req.org = org;
  next();
}
```

---

## 4 · Per-Tenant Configuration

### Tenant Settings
```typescript
const orgSettingsSchema = new Schema({
  org: { type: Types.ObjectId, ref: 'Org', unique: true },
  branding: {
    logo: String,
    favicon: String,
    primaryColor: { type: String, default: '#4F46E5' },
    appName: String,
  },
  features: {
    enablePublicPages: { type: Boolean, default: false },
    enableApi: { type: Boolean, default: false },
    enableExport: { type: Boolean, default: true },
  },
  integrations: {
    slack: { webhookUrl: String, enabled: Boolean },
    zapier: { apiKey: String, enabled: Boolean },
  },
  limits: {
    maxProjects: { type: Number, default: 10 },
    maxStorage: { type: Number, default: 1073741824 },
    maxApiCalls: { type: Number, default: 1000 },
  },
});
```

### White-Label API
```typescript
router.get('/tenant/branding', resolveTenant, async (req, res) => {
  const settings = await OrgSettings.findOne({ org: req.org.id });
  res.json({
    data: {
      name: settings?.branding?.appName || req.org.name,
      logo: settings?.branding?.logo,
      primaryColor: settings?.branding?.primaryColor || '#4F46E5',
      favicon: settings?.branding?.favicon,
    },
  });
});
```

---

## 5 · Data Isolation Patterns

### Row-Level Security
```typescript
// Every query MUST include org filter
// Create a base service with enforced scoping
class TenantService<T> {
  constructor(private model: Model<T>) {}

  async findAll(orgId: string, filters: Record<string, any> = {}) {
    return this.model.find({ org: orgId, ...filters });
  }

  async findById(orgId: string, id: string) {
    const doc = await this.model.findOne({ _id: id, org: orgId });
    if (!doc) throw new AppError(404, 'NOT_FOUND', 'Resource not found');
    return doc;
  }

  async create(orgId: string, data: Partial<T>) {
    return this.model.create({ ...data, org: orgId });
  }

  async update(orgId: string, id: string, data: Partial<T>) {
    const doc = await this.model.findOneAndUpdate(
      { _id: id, org: orgId },
      data,
      { new: true },
    );
    if (!doc) throw new AppError(404, 'NOT_FOUND', 'Resource not found');
    return doc;
  }

  async delete(orgId: string, id: string) {
    const doc = await this.model.findOneAndDelete({ _id: id, org: orgId });
    if (!doc) throw new AppError(404, 'NOT_FOUND', 'Resource not found');
    return doc;
  }
}

// Usage
const projectService = new TenantService(Project);
const projects = await projectService.findAll(req.org.id, { status: 'active' });
```

### File Storage Isolation
```
S3 bucket structure:
  s3://myapp-uploads/
    ├── org_abc123/
    │   ├── avatars/
    │   └── documents/
    └── org_def456/
        ├── avatars/
        └── documents/

// Enforce prefix in upload
const key = `${orgId}/${folder}/${filename}`;
```

---

## 6 · Multi-Tenant Checklist

```
Data Isolation:
✓ Every model has org field (indexed)
✓ Every query includes org filter (no exceptions)
✓ File storage scoped by org prefix
✓ API keys scoped to org
✓ Audit logs include org context

Routing:
✓ Subdomain detection + resolution
✓ Custom domain support (optional)
✓ Reserved subdomain list (www, api, app, admin)

Billing:
✓ Per-tenant Stripe customer
✓ Plan limits enforced (members, storage, API calls)
✓ Usage tracking per tenant per period
✓ Feature flags by plan

Security:
✓ Users cannot access other tenants' data
✓ Admin cannot escalate across tenants
✓ API rate limits per tenant
✓ Tenant-specific webhook secrets

✗ NEVER query without org filter
✗ NEVER expose tenant IDs in public URLs
✗ NEVER share cache keys across tenants
```

---
name: Admin Dashboard
category: pro
version: 1.0.0
description: >
  Build full admin panels. RBAC-protected admin routes, data tables, analytics, user management, audit logs, and bulk operations. React + Express.
author: Zaheer Shaik
tags:
  - admin
  - dashboard
  - rbac
  - react
  - pro
---

# Admin Dashboard — Claude Skill (Pro)

> Build full admin panels. RBAC-protected admin routes, data tables, analytics, user management, audit logs, bulk operations. React + Express.

---

## Core Directives

1. **Admin is a liability.** Every admin endpoint is a potential security breach — guard heavily.
2. **Audit everything.** Every admin action must be logged with who, what, when.
3. **Paginate and filter.** Admin panels deal with thousands of records — never load all.
4. **Separate from user routes.** Admin API is a different router with different middleware.

---

## 1 · Admin Route Architecture

### Separation
```typescript
// routes/admin.ts — separate router with admin-only middleware
import { Router } from 'express';
import { authenticate, authorize } from '../middleware/auth';

const adminRouter = Router();

// ALL admin routes require auth + admin role
adminRouter.use(authenticate);
adminRouter.use(authorize('admin'));
adminRouter.use(auditLogger); // log every admin action

adminRouter.get('/users', listUsers);
adminRouter.get('/users/:id', getUser);
adminRouter.patch('/users/:id', updateUser);
adminRouter.delete('/users/:id', deleteUser);
adminRouter.post('/users/:id/ban', banUser);
adminRouter.post('/users/:id/impersonate', impersonateUser);

adminRouter.get('/orgs', listOrgs);
adminRouter.get('/orgs/:id', getOrg);
adminRouter.patch('/orgs/:id/plan', changePlan);

adminRouter.get('/analytics', getDashboardAnalytics);
adminRouter.get('/audit-log', getAuditLog);

// Mount separately
app.use('/api/admin', adminRouter);
```

---

## 2 · Admin User Management

### List Users (Paginated + Filterable)
```typescript
export async function listUsers(req: Request, res: Response) {
  const { page = 1, limit = 25, search, role, status, sort = '-createdAt' } = req.query;
  const query: Record<string, any> = {};

  if (search) {
    query.$or = [
      { email: { $regex: search, $options: 'i' } },
      { name: { $regex: search, $options: 'i' } },
    ];
  }
  if (role) query.role = role;
  if (status === 'verified') query.emailVerified = true;
  if (status === 'unverified') query.emailVerified = false;
  if (status === 'banned') query.bannedAt = { $ne: null };

  const safePage = Math.max(1, Number(page));
  const safeLimit = Math.min(100, Math.max(1, Number(limit)));

  const [users, total] = await Promise.all([
    User.find(query)
      .select('email name role emailVerified createdAt lastLoginAt bannedAt')
      .sort(sort as string)
      .skip((safePage - 1) * safeLimit)
      .limit(safeLimit),
    User.countDocuments(query),
  ]);

  res.json({
    data: users,
    meta: { page: safePage, limit: safeLimit, total, totalPages: Math.ceil(total / safeLimit) },
  });
}
```

### Ban/Unban User
```typescript
export async function banUser(req: Request, res: Response) {
  const { id } = req.params;
  const { reason } = req.body;

  const user = await User.findById(id);
  if (!user) throw new AppError(404, 'NOT_FOUND', 'User not found');
  if (user.role === 'admin') throw new AppError(403, 'FORBIDDEN', 'Cannot ban admins');

  user.bannedAt = new Date();
  user.banReason = reason;
  await user.save();

  // Invalidate all sessions
  await User.updateOne({ _id: id }, { $set: { refreshTokens: [] } });

  await auditLog(req, 'user.banned', { targetUserId: id, reason });

  res.json({ data: { message: 'User banned', userId: id } });
}
```

### Impersonation (Support Tool)
```typescript
export async function impersonateUser(req: Request, res: Response) {
  const { id } = req.params;
  const user = await User.findById(id);
  if (!user) throw new AppError(404, 'NOT_FOUND', 'User not found');

  // Generate short-lived token with impersonation flag
  const token = jwt.sign(
    { sub: user.id, role: user.role, impersonatedBy: req.user.id },
    env.JWT_ACCESS_SECRET,
    { expiresIn: '30m' },
  );

  await auditLog(req, 'user.impersonated', { targetUserId: id });

  logger.warn({ adminId: req.user.id, targetUserId: id }, 'Admin impersonating user');

  res.json({ data: { accessToken: token, expiresIn: '30m' } });
}

// CRITICAL: Log impersonation banner in UI
// Show: "You are viewing as [user]. Actions are logged."
```

---

## 3 · Dashboard Analytics

### Summary Stats
```typescript
export async function getDashboardAnalytics(req: Request, res: Response) {
  const now = new Date();
  const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
  const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

  const [totalUsers, newUsers30d, newUsers7d, activeUsers7d, totalOrgs, revenue] = await Promise.all([
    User.countDocuments(),
    User.countDocuments({ createdAt: { $gte: thirtyDaysAgo } }),
    User.countDocuments({ createdAt: { $gte: sevenDaysAgo } }),
    User.countDocuments({ lastLoginAt: { $gte: sevenDaysAgo } }),
    Org.countDocuments(),
    getMonthlyRevenue(),
  ]);

  // Signup trend (daily for last 30 days)
  const signupTrend = await User.aggregate([
    { $match: { createdAt: { $gte: thirtyDaysAgo } } },
    { $group: { _id: { $dateToString: { format: '%Y-%m-%d', date: '$createdAt' } }, count: { $sum: 1 } } },
    { $sort: { _id: 1 } },
  ]);

  // Plan distribution
  const planDistribution = await Org.aggregate([
    { $group: { _id: '$plan', count: { $sum: 1 } } },
  ]);

  res.json({
    data: {
      stats: { totalUsers, newUsers30d, newUsers7d, activeUsers7d, totalOrgs, revenue },
      signupTrend,
      planDistribution,
    },
  });
}
```

---

## 4 · Audit Log

### Schema
```typescript
const auditLogSchema = new Schema({
  actor: { type: Types.ObjectId, ref: 'User', required: true, index: true },
  action: { type: String, required: true, index: true },
  target: {
    type: { type: String }, // 'user', 'org', 'post'
    id: Types.ObjectId,
  },
  metadata: Schema.Types.Mixed,
  ip: String,
  userAgent: String,
  createdAt: { type: Date, default: Date.now, index: true },
});

// TTL: auto-delete after 1 year
auditLogSchema.index({ createdAt: 1 }, { expireAfterSeconds: 365 * 24 * 60 * 60 });
```

### Logging Helper
```typescript
export async function auditLog(req: Request, action: string, metadata?: Record<string, any>) {
  await AuditLog.create({
    actor: req.user.id,
    action,
    target: metadata?.targetType ? { type: metadata.targetType, id: metadata.targetId } : undefined,
    metadata,
    ip: req.ip,
    userAgent: req.headers['user-agent'],
  });
}

// Auto-audit middleware for all admin routes
export function auditLogger(req: Request, res: Response, next: NextFunction) {
  const originalSend = res.send;
  res.send = function (body) {
    if (res.statusCode < 400 && req.method !== 'GET') {
      auditLog(req, `admin.${req.method.toLowerCase()}.${req.path}`, {
        statusCode: res.statusCode,
      }).catch(err => logger.error({ err }, 'Audit log failed'));
    }
    return originalSend.call(this, body);
  };
  next();
}
```

### Query Audit Log
```typescript
router.get('/audit-log', async (req, res) => {
  const { page = 1, limit = 50, actor, action, startDate, endDate } = req.query;
  const query: Record<string, any> = {};

  if (actor) query.actor = actor;
  if (action) query.action = { $regex: action, $options: 'i' };
  if (startDate || endDate) {
    query.createdAt = {};
    if (startDate) query.createdAt.$gte = new Date(startDate as string);
    if (endDate) query.createdAt.$lte = new Date(endDate as string);
  }

  const [logs, total] = await Promise.all([
    AuditLog.find(query)
      .populate('actor', 'name email')
      .sort({ createdAt: -1 })
      .skip((Number(page) - 1) * Number(limit))
      .limit(Number(limit)),
    AuditLog.countDocuments(query),
  ]);

  res.json({ data: logs, meta: { page: Number(page), limit: Number(limit), total } });
});
```

---

## 5 · Bulk Operations

```typescript
// Bulk update users
router.post('/users/bulk', async (req, res) => {
  const { userIds, action, data } = z.object({
    userIds: z.array(z.string()).min(1).max(100),
    action: z.enum(['ban', 'unban', 'changeRole', 'delete']),
    data: z.record(z.any()).optional(),
  }).parse(req.body);

  let result;
  switch (action) {
    case 'ban':
      result = await User.updateMany(
        { _id: { $in: userIds }, role: { $ne: 'admin' } },
        { $set: { bannedAt: new Date(), banReason: data?.reason } },
      );
      break;
    case 'changeRole':
      result = await User.updateMany(
        { _id: { $in: userIds } },
        { $set: { role: data?.role } },
      );
      break;
    case 'delete':
      result = await User.updateMany(
        { _id: { $in: userIds }, role: { $ne: 'admin' } },
        { $set: { deletedAt: new Date() } },
      );
      break;
  }

  await auditLog(req, `admin.bulk.${action}`, { userIds, count: result.modifiedCount });

  res.json({ data: { modified: result.modifiedCount } });
});
```

---

## 6 · Admin Security Checklist

```
Access:
✓ Admin routes on separate path (/api/admin)
✓ Role-based middleware on every route
✓ Admin actions require re-authentication for sensitive ops
✓ IP whitelist for admin routes (optional, enterprise)

Audit:
✓ Every write operation logged with actor, action, target
✓ Impersonation logged and time-limited
✓ Bulk operations logged with full user list
✓ Audit logs immutable and retained 1+ year

Protection:
✓ Rate limit admin endpoints (stricter than user endpoints)
✓ Cannot ban/delete other admins
✓ Cannot escalate own role
✓ Impersonation tokens short-lived (30 min max)
✓ Admin sessions require MFA (if available)
```

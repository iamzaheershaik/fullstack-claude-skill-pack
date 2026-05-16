---
name: SaaS Boilerplate
category: pro
version: 1.0.0
description: >
  Build a complete SaaS application from scratch. Auth, billing, teams, dashboards, onboarding, and feature flags. MERN + Stripe. Ship in days, not months.
author: Zaheer Shaik
tags:
  - saas
  - boilerplate
  - stripe
  - mern
  - pro
---

# SaaS Boilerplate — Claude Skill (Pro)

> Build a complete SaaS application from scratch. Auth, billing, teams, dashboards, onboarding, feature flags. MERN + Stripe. Ship in days, not months.

---

## Core Directives

1. **SaaS is a business, not a project.** Every technical decision maps to revenue impact.
2. **Multi-tenant from day one.** Retrofitting tenant isolation is 10x harder.
3. **Billing is the product.** If users can't pay, nothing else matters.
4. **Self-serve everything.** Users should never need to email you to manage their account.

---

## 1 · SaaS Architecture

### System Overview
```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  React SPA  │────▶│  Express API │────▶│  MongoDB    │
│  (Vite)     │     │  + Stripe    │     │  (Atlas)    │
└─────────────┘     └──────────────┘     └─────────────┘
                           │
                    ┌──────┴──────┐
                    │   Redis     │  (sessions, cache, queues)
                    └─────────────┘
```

### Database Schema
```typescript
// Organization (tenant)
const orgSchema = new Schema({
  name: { type: String, required: true, trim: true },
  slug: { type: String, required: true, unique: true, lowercase: true },
  owner: { type: Types.ObjectId, ref: 'User', required: true },
  plan: { type: String, enum: ['free', 'starter', 'pro', 'enterprise'], default: 'free' },
  stripeCustomerId: { type: String, select: false },
  stripeSubscriptionId: { type: String, select: false },
  subscriptionStatus: {
    type: String,
    enum: ['active', 'past_due', 'canceled', 'trialing', 'unpaid'],
    default: 'trialing',
  },
  trialEndsAt: { type: Date, default: () => new Date(Date.now() + 14 * 24 * 60 * 60 * 1000) },
  settings: {
    logo: String,
    timezone: { type: String, default: 'UTC' },
    features: { type: Map, of: Boolean, default: {} },
  },
  limits: {
    members: { type: Number, default: 5 },
    storage: { type: Number, default: 1073741824 }, // 1GB in bytes
    apiCalls: { type: Number, default: 1000 },
  },
}, { timestamps: true });

// Membership (user ↔ org join table)
const membershipSchema = new Schema({
  user: { type: Types.ObjectId, ref: 'User', required: true },
  org: { type: Types.ObjectId, ref: 'Org', required: true },
  role: { type: String, enum: ['owner', 'admin', 'member', 'viewer'], default: 'member' },
  invitedBy: { type: Types.ObjectId, ref: 'User' },
  invitedAt: Date,
  joinedAt: { type: Date, default: Date.now },
}, { timestamps: true });
membershipSchema.index({ user: 1, org: 1 }, { unique: true });

// User
const userSchema = new Schema({
  email: { type: String, required: true, unique: true, lowercase: true },
  password: { type: String, required: true, select: false },
  name: { type: String, required: true, trim: true },
  avatar: String,
  defaultOrg: { type: Types.ObjectId, ref: 'Org' },
  emailVerified: { type: Boolean, default: false },
  lastLoginAt: Date,
}, { timestamps: true });
```

### Plan Configuration
```typescript
export const PLANS = {
  free: {
    name: 'Free',
    price: 0,
    limits: { members: 3, storage: 524288000, apiCalls: 500 },
    features: ['basic_dashboard', 'email_support'],
  },
  starter: {
    name: 'Starter',
    price: 29,
    stripePriceId: process.env.STRIPE_STARTER_PRICE_ID,
    limits: { members: 10, storage: 5368709120, apiCalls: 5000 },
    features: ['basic_dashboard', 'advanced_analytics', 'api_access', 'email_support'],
  },
  pro: {
    name: 'Pro',
    price: 79,
    stripePriceId: process.env.STRIPE_PRO_PRICE_ID,
    limits: { members: 50, storage: 53687091200, apiCalls: 50000 },
    features: ['basic_dashboard', 'advanced_analytics', 'api_access', 'custom_domain',
               'priority_support', 'sso', 'audit_log'],
  },
  enterprise: {
    name: 'Enterprise',
    price: null, // custom pricing
    limits: { members: Infinity, storage: Infinity, apiCalls: Infinity },
    features: ['*'],
  },
} as const;

// Check feature access
export function hasFeature(plan: string, feature: string): boolean {
  const planConfig = PLANS[plan];
  return planConfig.features.includes('*') || planConfig.features.includes(feature);
}

// Check limit
export function withinLimit(plan: string, resource: string, current: number): boolean {
  return current < PLANS[plan].limits[resource];
}
```

---

## 2 · Team Management

### Invite Flow
```typescript
export async function inviteMember(orgId: string, email: string, role: string, invitedBy: string) {
  const org = await Org.findById(orgId);
  const memberCount = await Membership.countDocuments({ org: orgId });

  if (!withinLimit(org.plan, 'members', memberCount)) {
    throw new AppError(403, 'PLAN_LIMIT', `${PLANS[org.plan].name} plan allows ${PLANS[org.plan].limits.members} members`);
  }

  let user = await User.findOne({ email });
  const isNewUser = !user;

  if (isNewUser) {
    user = await User.create({ email, name: email.split('@')[0], password: crypto.randomBytes(32).toString('hex') });
  }

  const existing = await Membership.findOne({ user: user.id, org: orgId });
  if (existing) throw new AppError(409, 'ALREADY_MEMBER', 'User is already a member');

  await Membership.create({ user: user.id, org: orgId, role, invitedBy, invitedAt: new Date() });

  // Send invite email
  const token = jwt.sign({ userId: user.id, orgId }, env.JWT_ACCESS_SECRET, { expiresIn: '7d' });
  await emailService.send({
    to: email,
    template: isNewUser ? 'invite-new-user' : 'invite-existing-user',
    data: { orgName: org.name, inviteUrl: `${env.APP_URL}/invite/${token}`, role },
  });

  return { user: { id: user.id, email }, role };
}
```

### Role Permissions Matrix
```typescript
const TEAM_PERMISSIONS = {
  owner:  ['org:delete', 'org:settings', 'billing:manage', 'members:manage', 'members:invite', 'content:*'],
  admin:  ['org:settings', 'members:manage', 'members:invite', 'content:*'],
  member: ['members:invite', 'content:create', 'content:read', 'content:update_own'],
  viewer: ['content:read'],
} as const;
```

### Org Context Middleware
```typescript
export async function requireOrg(req: Request, _res: Response, next: NextFunction) {
  const orgId = req.headers['x-org-id'] as string || req.params.orgId;
  if (!orgId) throw new AppError(400, 'MISSING_ORG', 'Organization ID required');

  const membership = await Membership.findOne({ user: req.user.id, org: orgId });
  if (!membership) throw new AppError(403, 'NOT_MEMBER', 'Not a member of this organization');

  req.org = await Org.findById(orgId);
  req.membership = membership;
  next();
}

export function requireOrgRole(...roles: string[]) {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!roles.includes(req.membership.role))
      throw new AppError(403, 'FORBIDDEN', 'Insufficient role');
    next();
  };
}
```

---

## 3 · Onboarding Flow

### Steps
```
1. Sign up (email + password)
2. Verify email
3. Create organization (name, slug)
4. Choose plan (free trial auto-starts)
5. Invite team (optional, skip-able)
6. Dashboard
```

### Onboarding State
```typescript
export function getOnboardingState(user: User, org?: Org) {
  const steps = [
    { id: 'verify_email', done: user.emailVerified },
    { id: 'create_org', done: !!org },
    { id: 'choose_plan', done: org?.plan !== 'free' || org?.trialEndsAt },
    { id: 'invite_team', done: true, skippable: true },
  ];

  const currentStep = steps.find(s => !s.done && !s.skippable);
  return { steps, currentStep: currentStep?.id || 'complete', progress: steps.filter(s => s.done).length / steps.length };
}
```

---

## 4 · Dashboard Patterns

### API Routes
```typescript
// Dashboard summary — single aggregation endpoint
router.get('/dashboard', authenticate, requireOrg, async (req, res) => {
  const [stats, recentActivity, usage] = await Promise.all([
    getDashboardStats(req.org.id),
    getRecentActivity(req.org.id, 10),
    getUsageMetrics(req.org.id, req.org.plan),
  ]);

  res.json({ data: { stats, recentActivity, usage } });
});

async function getDashboardStats(orgId: string) {
  const [members, projects, apiCalls] = await Promise.all([
    Membership.countDocuments({ org: orgId }),
    Project.countDocuments({ org: orgId }),
    Usage.aggregate([
      { $match: { org: new Types.ObjectId(orgId), period: getCurrentPeriod() } },
      { $group: { _id: null, total: { $sum: '$count' } } },
    ]),
  ]);
  return { members, projects, apiCalls: apiCalls[0]?.total || 0 };
}
```

### Usage Tracking
```typescript
// Track API usage per org per billing period
const usageSchema = new Schema({
  org: { type: Types.ObjectId, ref: 'Org', required: true, index: true },
  resource: { type: String, required: true }, // 'api_calls', 'storage', 'emails'
  count: { type: Number, default: 0 },
  period: { type: String, required: true }, // '2024-01'
});
usageSchema.index({ org: 1, resource: 1, period: 1 }, { unique: true });

export async function incrementUsage(orgId: string, resource: string, amount = 1) {
  const period = new Date().toISOString().slice(0, 7);
  await Usage.updateOne(
    { org: orgId, resource, period },
    { $inc: { count: amount } },
    { upsert: true },
  );
}

// Middleware to check limits
export function checkUsageLimit(resource: string) {
  return async (req: Request, _res: Response, next: NextFunction) => {
    const period = new Date().toISOString().slice(0, 7);
    const usage = await Usage.findOne({ org: req.org.id, resource, period });
    const limit = PLANS[req.org.plan].limits[resource];

    if (usage && usage.count >= limit) {
      throw new AppError(429, 'LIMIT_EXCEEDED', `${resource} limit reached. Upgrade your plan.`);
    }
    next();
  };
}
```

---

## 5 · Feature Flags

```typescript
// Check feature access in routes
export function requireFeature(feature: string) {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!hasFeature(req.org.plan, feature)) {
      throw new AppError(403, 'FEATURE_LOCKED', `${feature} requires a higher plan`, {
        requiredPlan: getMinPlanForFeature(feature),
        currentPlan: req.org.plan,
      });
    }
    next();
  };
}

// Usage
router.get('/analytics', authenticate, requireOrg, requireFeature('advanced_analytics'), getAnalytics);

// Frontend: conditional rendering
function FeatureGate({ feature, children, fallback }: FeatureGateProps) {
  const { org } = useOrg();
  if (!hasFeature(org.plan, feature)) return fallback || <UpgradePrompt feature={feature} />;
  return children;
}
```

---

## 6 · Environment Variables

```env
# App
APP_URL=https://yourapp.com
NODE_ENV=production

# Database
MONGO_URI=mongodb+srv://...
REDIS_URL=redis://...

# Auth
JWT_ACCESS_SECRET=
JWT_REFRESH_SECRET=

# Stripe
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
STRIPE_STARTER_PRICE_ID=price_...
STRIPE_PRO_PRICE_ID=price_...

# Email
RESEND_API_KEY=re_...
EMAIL_FROM=noreply@yourapp.com

# Sentry
SENTRY_DSN=https://...
```

---

## 7 · SaaS Launch Checklist

```
Pre-Launch:
✓ Auth flow (signup → verify → login → forgot password)
✓ Org creation + team invites
✓ Stripe integration (plans, checkout, portal, webhooks)
✓ Feature flags by plan
✓ Usage tracking + limit enforcement
✓ Dashboard with key metrics
✓ Settings page (org, profile, billing)
✓ Onboarding flow

Launch:
✓ Landing page with pricing table
✓ Legal pages (privacy, terms, acceptable use)
✓ Transactional emails (welcome, invite, receipt, dunning)
✓ Error tracking (Sentry)
✓ Uptime monitoring
✓ Analytics (Plausible / PostHog)
✓ Customer support channel

Post-Launch:
✓ Dunning emails for failed payments
✓ Churn analysis
✓ NPS / feedback collection
✓ Audit log for enterprise
✓ SSO for enterprise
```

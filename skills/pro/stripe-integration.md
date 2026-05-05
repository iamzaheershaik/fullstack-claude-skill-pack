# Stripe Integration — Claude Skill (Pro)

> Implement complete payment infrastructure. Checkout, subscriptions, webhooks, customer portal, invoices, metered billing, dunning. Node.js + Stripe API.

---

## Core Directives

1. **Webhooks are the source of truth.** Never trust client-side payment confirmations.
2. **Idempotent everything.** Stripe sends webhooks multiple times — handle it.
3. **Test with Stripe CLI.** Never test payments against production.
4. **Handle every edge case.** Failed payments, disputes, refunds, plan changes mid-cycle.

---

## 1 · Stripe Setup

### Install & Configure
```typescript
import Stripe from 'stripe';

export const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: '2024-04-10',
  typescript: true,
});
```

### Product & Price Setup (One-time in Stripe Dashboard or API)
```typescript
// Create products + prices via API (run once)
async function setupStripePlans() {
  const product = await stripe.products.create({
    name: 'SaaS Pro Plan',
    description: 'Full access to all features',
  });

  const monthlyPrice = await stripe.prices.create({
    product: product.id,
    unit_amount: 7900, // $79.00
    currency: 'usd',
    recurring: { interval: 'month' },
    lookup_key: 'pro_monthly',
  });

  const yearlyPrice = await stripe.prices.create({
    product: product.id,
    unit_amount: 79000, // $790.00 (save ~17%)
    currency: 'usd',
    recurring: { interval: 'year' },
    lookup_key: 'pro_yearly',
  });

  console.log({ product: product.id, monthlyPrice: monthlyPrice.id, yearlyPrice: yearlyPrice.id });
}
```

---

## 2 · Checkout Flow

### Create Checkout Session
```typescript
export async function createCheckoutSession(orgId: string, priceId: string, userId: string) {
  const org = await Org.findById(orgId).select('+stripeCustomerId');

  // Create or retrieve Stripe customer
  let customerId = org.stripeCustomerId;
  if (!customerId) {
    const user = await User.findById(userId);
    const customer = await stripe.customers.create({
      email: user.email,
      name: org.name,
      metadata: { orgId, userId },
    });
    customerId = customer.id;
    org.stripeCustomerId = customerId;
    await org.save();
  }

  const session = await stripe.checkout.sessions.create({
    customer: customerId,
    mode: 'subscription',
    line_items: [{ price: priceId, quantity: 1 }],
    success_url: `${env.APP_URL}/billing?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${env.APP_URL}/billing`,
    subscription_data: {
      trial_period_days: 14,
      metadata: { orgId },
    },
    allow_promotion_codes: true,
    billing_address_collection: 'auto',
    tax_id_collection: { enabled: true },
    metadata: { orgId, userId },
  });

  return { url: session.url };
}

// Route
router.post('/checkout', authenticate, requireOrg, requireOrgRole('owner', 'admin'), async (req, res) => {
  const { priceId } = z.object({ priceId: z.string() }).parse(req.body);
  const session = await createCheckoutSession(req.org.id, priceId, req.user.id);
  res.json({ data: session });
});
```

### Customer Portal (Manage Subscription)
```typescript
export async function createPortalSession(orgId: string) {
  const org = await Org.findById(orgId).select('+stripeCustomerId');
  if (!org.stripeCustomerId) throw new AppError(400, 'NO_SUBSCRIPTION', 'No billing account found');

  const session = await stripe.billingPortal.sessions.create({
    customer: org.stripeCustomerId,
    return_url: `${env.APP_URL}/billing`,
  });

  return { url: session.url };
}
```

---

## 3 · Webhook Handler

### Setup
```typescript
// IMPORTANT: raw body required for signature verification
app.post('/webhooks/stripe',
  express.raw({ type: 'application/json' }),
  async (req, res) => {
    const sig = req.headers['stripe-signature'] as string;
    let event: Stripe.Event;

    try {
      event = stripe.webhooks.constructEvent(req.body, sig, env.STRIPE_WEBHOOK_SECRET);
    } catch (err) {
      logger.error({ err }, 'Stripe webhook signature verification failed');
      return res.status(400).send('Invalid signature');
    }

    try {
      await handleStripeEvent(event);
      res.json({ received: true });
    } catch (err) {
      logger.error({ err, eventType: event.type }, 'Stripe webhook handler error');
      res.status(500).json({ error: 'Webhook handler failed' });
    }
  },
);
```

### Event Handler
```typescript
async function handleStripeEvent(event: Stripe.Event) {
  // Idempotency: check if already processed
  const processed = await WebhookEvent.findOne({ stripeEventId: event.id });
  if (processed) return;

  switch (event.type) {
    case 'checkout.session.completed':
      await handleCheckoutComplete(event.data.object as Stripe.Checkout.Session);
      break;

    case 'customer.subscription.created':
    case 'customer.subscription.updated':
      await handleSubscriptionChange(event.data.object as Stripe.Subscription);
      break;

    case 'customer.subscription.deleted':
      await handleSubscriptionCanceled(event.data.object as Stripe.Subscription);
      break;

    case 'invoice.payment_succeeded':
      await handlePaymentSuccess(event.data.object as Stripe.Invoice);
      break;

    case 'invoice.payment_failed':
      await handlePaymentFailed(event.data.object as Stripe.Invoice);
      break;

    default:
      logger.info({ type: event.type }, 'Unhandled Stripe event');
  }

  // Mark as processed
  await WebhookEvent.create({ stripeEventId: event.id, type: event.type, processedAt: new Date() });
}

async function handleSubscriptionChange(subscription: Stripe.Subscription) {
  const orgId = subscription.metadata.orgId;
  if (!orgId) return;

  const priceId = subscription.items.data[0]?.price.id;
  const plan = Object.entries(PLANS).find(([_, p]) => p.stripePriceId === priceId)?.[0] || 'free';

  await Org.findByIdAndUpdate(orgId, {
    plan,
    stripeSubscriptionId: subscription.id,
    subscriptionStatus: subscription.status,
    limits: PLANS[plan].limits,
  });

  logger.info({ orgId, plan, status: subscription.status }, 'Subscription updated');
}

async function handleSubscriptionCanceled(subscription: Stripe.Subscription) {
  const orgId = subscription.metadata.orgId;
  if (!orgId) return;

  await Org.findByIdAndUpdate(orgId, {
    plan: 'free',
    subscriptionStatus: 'canceled',
    limits: PLANS.free.limits,
  });

  await emailService.send({
    to: await getOrgOwnerEmail(orgId),
    template: 'subscription-canceled',
    data: { orgName: (await Org.findById(orgId)).name },
  });
}

async function handlePaymentFailed(invoice: Stripe.Invoice) {
  const customerId = invoice.customer as string;
  const org = await Org.findOne({ stripeCustomerId: customerId });
  if (!org) return;

  await Org.findByIdAndUpdate(org.id, { subscriptionStatus: 'past_due' });

  await emailService.send({
    to: await getOrgOwnerEmail(org.id),
    template: 'payment-failed',
    data: {
      orgName: org.name,
      amount: (invoice.amount_due / 100).toFixed(2),
      updateUrl: `${env.APP_URL}/billing`,
      attemptCount: invoice.attempt_count,
    },
  });
}
```

---

## 4 · Subscription Management

### Change Plan
```typescript
export async function changePlan(orgId: string, newPriceId: string) {
  const org = await Org.findById(orgId).select('+stripeSubscriptionId');
  if (!org.stripeSubscriptionId) throw new AppError(400, 'NO_SUBSCRIPTION', 'No active subscription');

  const subscription = await stripe.subscriptions.retrieve(org.stripeSubscriptionId);

  await stripe.subscriptions.update(org.stripeSubscriptionId, {
    items: [{ id: subscription.items.data[0].id, price: newPriceId }],
    proration_behavior: 'always_invoice', // charge/credit immediately
  });
}
```

### Cancel Subscription
```typescript
export async function cancelSubscription(orgId: string) {
  const org = await Org.findById(orgId).select('+stripeSubscriptionId');
  if (!org.stripeSubscriptionId) throw new AppError(400, 'NO_SUBSCRIPTION', 'No active subscription');

  // Cancel at period end (user keeps access until billing period ends)
  await stripe.subscriptions.update(org.stripeSubscriptionId, {
    cancel_at_period_end: true,
  });
}
```

---

## 5 · Metered / Usage-Based Billing

```typescript
// Report usage to Stripe
export async function reportUsage(orgId: string, quantity: number) {
  const org = await Org.findById(orgId).select('+stripeSubscriptionId');
  const subscription = await stripe.subscriptions.retrieve(org.stripeSubscriptionId);
  const meteredItem = subscription.items.data.find(i => i.price.recurring?.usage_type === 'metered');

  if (!meteredItem) return;

  await stripe.subscriptionItems.createUsageRecord(meteredItem.id, {
    quantity,
    timestamp: Math.floor(Date.now() / 1000),
    action: 'increment',
  });
}
```

---

## 6 · Testing

### Stripe CLI (Local Webhook Testing)
```bash
# Install: https://stripe.com/docs/stripe-cli
stripe login
stripe listen --forward-to localhost:3000/webhooks/stripe

# Trigger test events
stripe trigger checkout.session.completed
stripe trigger invoice.payment_failed
stripe trigger customer.subscription.deleted
```

### Test Cards
| Card Number | Scenario |
|---|---|
| `4242 4242 4242 4242` | Success |
| `4000 0000 0000 9995` | Declined |
| `4000 0000 0000 0341` | Attach succeeds, charge fails |
| `4000 0025 0000 3155` | Requires 3D Secure |

---

## 7 · Webhook Events Checklist

```
Must handle:
✓ checkout.session.completed — activate subscription
✓ customer.subscription.updated — plan change, renewal
✓ customer.subscription.deleted — cancellation
✓ invoice.payment_succeeded — record payment
✓ invoice.payment_failed — dunning, notify user

Should handle:
✓ customer.updated — email/name changes
✓ charge.refunded — update records
✓ charge.dispute.created — alert team

✓ Verify webhook signature (ALWAYS)
✓ Handle idempotently (check event ID)
✓ Return 200 quickly (process async if heavy)
✓ Log every event for debugging
```

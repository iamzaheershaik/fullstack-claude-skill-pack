# BakeRoute — AI Agent Chunk Prompts
> Feed each chunk to your AI coding agent (Claude Code / Cursor) one at a time.
> Wait for ✅ DONE confirmation + working code before moving to next chunk.
> Stack: Node.js (Express) + React (Vite) + PostgreSQL + Redis + MongoDB | Pure JavaScript, no TypeScript

---

## HOW TO USE THESE PROMPTS

1. Start a fresh Claude Code / Cursor session
2. Paste **Chunk 1** exactly as written
3. Agent builds → you review → mark done in `tasks/todo.md`
4. Paste **Chunk 2** in the same session (agent has context) OR new session
5. Always run `tasks/todo.md` check before next chunk

---

## PHASE 1 — MONOREPO FOUNDATION

---

### 🧱 CHUNK 1 — Monorepo Scaffold + Docker Dev Environment

```
You are building BakeRoute — a hyperlocal bakery delivery marketplace for India.

## TASK: Set up the monorepo scaffold with Docker Compose dev environment.

### Monorepo structure to create:
bakeroute/
├── packages/
│   ├── api/          # Express.js backend (Node.js, plain JS)
│   ├── web/          # React (Vite) customer-facing web app
│   ├── vendor/       # React (Vite) bakery vendor dashboard
│   ├── agent/        # React (Vite) delivery agent PWA
│   └── shared/       # Shared validators (Zod schemas), constants, utils
├── docker-compose.yml
├── .env.example
├── tasks/
│   ├── todo.md
│   └── lessons.md
└── package.json      # Workspace root

### Docker Compose services:
- postgres:15 — port 5432, DB name: bakeroute_dev
- redis:7 — port 6379
- mongo:7 — port 27017, DB name: bakeroute_tracking

### packages/api setup:
- Express.js app (plain JS, no TypeScript)
- Use npm workspaces
- Install: express, cors, helmet, dotenv, express-rate-limit, zod, pg, ioredis, mongoose, uuid, bcrypt, jsonwebtoken, axios
- Install dev: nodemon, jest, supertest

### packages/web, packages/vendor, packages/agent:
- Vite + React (plain JS template, no TypeScript)
- Install: react-router-dom, axios, zustand, react-hook-form

### packages/api folder structure:
src/
├── config/
│   └── index.js         # env validation with dotenv
├── db/
│   ├── postgres.js      # pg Pool setup
│   ├── redis.js         # ioredis client
│   └── mongo.js         # mongoose connection
├── middleware/
│   ├── auth.js          # JWT verify middleware
│   ├── errorHandler.js  # centralized error handler
│   └── rateLimiter.js   # express-rate-limit with Redis store
├── modules/             # feature modules (empty for now)
├── lib/
│   └── AppError.js      # Custom error classes
└── app.js               # Express app bootstrap

### packages/api/src/app.js must include:
- helmet(), cors(), express.json()
- GET /healthz → returns { status: 'ok', db: 'connected', redis: 'connected' }
- Global error handler middleware (last)
- Graceful shutdown on SIGTERM (drain connections)

### .env.example must include ALL required env vars:
DATABASE_URL, REDIS_URL, MONGODB_URL, JWT_SECRET, JWT_REFRESH_SECRET,
JWT_ACCESS_EXPIRY=15m, JWT_REFRESH_EXPIRY=30d,
RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET, RAZORPAY_WEBHOOK_SECRET,
OPENAI_API_KEY, S3_BUCKET, S3_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
SMS_API_KEY, PLATFORM_FEE_PERCENT=10, PORT=4000, NODE_ENV=development

### tasks/todo.md initial content:
# BakeRoute Build Progress
- [x] Chunk 1: Monorepo + Docker setup
- [ ] Chunk 2: PostgreSQL schema + migrations
- [ ] Chunk 3: Auth service (OTP + JWT)
- [ ] Chunk 4: Catalog service (bakeries + products)
- [ ] Chunk 5: Order service (state machine)
- [ ] Chunk 6: Payment service (Razorpay)
- [ ] Chunk 7: Delivery assignment service
- [ ] Chunk 8: Real-time tracking (WebSocket + MongoDB)
- [ ] Chunk 9: Notification service
- [ ] Chunk 10: Customer web app — Browse & Search
- [ ] Chunk 11: Customer web app — Order placement + AI preview
- [ ] Chunk 12: Customer web app — Tracking UI
- [ ] Chunk 13: Vendor dashboard
- [ ] Chunk 14: Agent PWA
- [ ] Chunk 15: CI/CD pipeline

DELIVER: All files created. `docker compose up` must start all 3 DB services.
Run `npm run dev` in packages/api must start Express on port 4000 with /healthz returning 200.
```

---

## PHASE 2 — DATABASE & AUTH

---

### 🗃️ CHUNK 2 — PostgreSQL Schema + Migrations

```
Context: BakeRoute monorepo is set up. packages/api is running.

## TASK: Create PostgreSQL schema with all migrations for BakeRoute.

### Create packages/api/src/db/migrations/ with numbered SQL files:

**001_create_users.sql**
CREATE TABLE users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone         VARCHAR(15) UNIQUE NOT NULL,
  email         VARCHAR(255),
  name          VARCHAR(100),
  role          VARCHAR(20) NOT NULL CHECK (role IN ('customer','bakery_owner','agent','admin')),
  is_active     BOOLEAN DEFAULT true,
  fcm_token     VARCHAR(500),           -- Firebase push notification token
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

**002_create_bakeries.sql**
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE TABLE bakeries (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id        UUID REFERENCES users(id),
  name            VARCHAR(200) NOT NULL,
  slug            VARCHAR(200) UNIQUE NOT NULL,
  description     TEXT,
  location        GEOGRAPHY(POINT,4326),
  address         JSONB NOT NULL,       -- {line1, line2, city, pincode}
  city            VARCHAR(100) NOT NULL,
  rating          NUMERIC(3,2) DEFAULT 0.0,
  rating_count    INTEGER DEFAULT 0,
  is_active       BOOLEAN DEFAULT true,
  operating_hours JSONB,                -- {"mon":{"open":"08:00","close":"20:00"}}
  max_daily_orders INTEGER DEFAULT 50,
  advance_hours   INTEGER DEFAULT 24,
  cover_image     VARCHAR(500),
  images          TEXT[],
  created_at      TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_bakeries_city ON bakeries(city, is_active);
CREATE INDEX idx_bakeries_location ON bakeries USING GIST(location);

**003_create_products.sql**
CREATE TABLE products (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bakery_id           UUID REFERENCES bakeries(id) ON DELETE CASCADE,
  name                VARCHAR(200) NOT NULL,
  description         TEXT,
  base_price          NUMERIC(10,2) NOT NULL,
  category            VARCHAR(50) NOT NULL CHECK (category IN ('cake','pastry','bread','cookie','custom','other')),
  is_customizable     BOOLEAN DEFAULT false,
  customization_schema JSONB,           -- {flavors:[], tiers:[], message: true, design_styles:[]}
  images              TEXT[],
  is_available        BOOLEAN DEFAULT true,
  sort_order          INTEGER DEFAULT 0,
  created_at          TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_products_bakery ON products(bakery_id, is_available);

**004_create_orders.sql**
CREATE TABLE orders (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  idempotency_key   UUID UNIQUE NOT NULL,
  customer_id       UUID REFERENCES users(id),
  bakery_id         UUID REFERENCES bakeries(id),
  status            VARCHAR(30) NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','confirmed','preparing','ready','assigned','picked','delivered','cancelled','refund_requested','refunded')),
  items             JSONB NOT NULL,
  customization     JSONB,
  delivery_address  JSONB NOT NULL,
  delivery_location GEOGRAPHY(POINT,4326),
  scheduled_at      TIMESTAMPTZ NOT NULL,
  subtotal          NUMERIC(10,2) NOT NULL,
  platform_fee      NUMERIC(10,2) NOT NULL,
  delivery_fee      NUMERIC(10,2) NOT NULL,
  total             NUMERIC(10,2) NOT NULL,
  payment_status    VARCHAR(20) DEFAULT 'pending' CHECK (payment_status IN ('pending','captured','failed','refunded')),
  razorpay_order_id VARCHAR(100),
  special_notes     TEXT,
  cancelled_reason  TEXT,
  cancelled_by      VARCHAR(20),
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  updated_at        TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_orders_bakery ON orders(bakery_id, status);
CREATE INDEX idx_orders_customer ON orders(customer_id, created_at DESC);
CREATE INDEX idx_orders_scheduled ON orders(scheduled_at, status);

**005_create_payment_events.sql**
CREATE TABLE payment_events (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id     UUID REFERENCES orders(id),
  event_type   VARCHAR(30) NOT NULL CHECK (event_type IN ('initiated','captured','failed','refunded','settled')),
  amount       NUMERIC(10,2) NOT NULL,
  currency     VARCHAR(5) DEFAULT 'INR',
  gateway_ref  VARCHAR(200),
  metadata     JSONB,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);
-- Append-only: NO UPDATE permissions on this table

**006_create_delivery_assignments.sql**
CREATE TABLE delivery_assignments (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id     UUID REFERENCES orders(id) UNIQUE,
  agent_id     UUID REFERENCES users(id),
  status       VARCHAR(30) DEFAULT 'assigned'
               CHECK (status IN ('assigned','en_route_bakery','at_bakery','en_route_customer','delivered')),
  pickup_code  VARCHAR(10) NOT NULL,
  assigned_at  TIMESTAMPTZ DEFAULT NOW(),
  picked_at    TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  distance_km  NUMERIC(8,2),
  agent_fee    NUMERIC(10,2)
);

**007_create_ratings.sql**
CREATE TABLE ratings (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id     UUID REFERENCES orders(id) UNIQUE,
  customer_id  UUID REFERENCES users(id),
  bakery_id    UUID REFERENCES bakeries(id),
  agent_id     UUID REFERENCES users(id),
  bakery_stars SMALLINT CHECK (bakery_stars BETWEEN 1 AND 5),
  agent_stars  SMALLINT CHECK (agent_stars BETWEEN 1 AND 5),
  review_text  TEXT,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

**008_create_otp_requests.sql**
CREATE TABLE otp_requests (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone        VARCHAR(15) NOT NULL,
  otp_hash     VARCHAR(255) NOT NULL,   -- bcrypt hash, never store plain OTP
  expires_at   TIMESTAMPTZ NOT NULL,
  used         BOOLEAN DEFAULT false,
  attempts     SMALLINT DEFAULT 0,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_otp_phone ON otp_requests(phone, created_at DESC);

### Create packages/api/src/db/migrate.js:
- Reads all SQL files from migrations/ in order
- Runs each in a transaction
- Creates a schema_migrations table to track applied migrations
- Idempotent — skip already-applied migrations

### Update packages/api/package.json scripts:
"migrate": "node src/db/migrate.js",
"migrate:fresh": "node src/db/migrate.js --fresh"

DELIVER: All migration files created. `npm run migrate` runs successfully against Docker postgres.
Show the final table list confirming all 8 tables exist.
```

---

### 🔐 CHUNK 3 — Auth Service (OTP + JWT)

```
Context: PostgreSQL schema is migrated. otp_requests and users tables exist.

## TASK: Build the complete Auth module — OTP send/verify + JWT issue/refresh + middleware.

### Create packages/api/src/modules/auth/:

**validator.js** — Zod schemas:
- SendOtpDto: { phone: z.string().regex(/^[6-9]\d{9}$/) }
- VerifyOtpDto: { phone, otp: z.string().length(6), request_id: z.string().uuid() }
- RefreshTokenDto: { refresh_token: z.string() }

**repository.js** — DB queries only, no business logic:
- createOtpRequest(phone, otpHash, expiresAt)
- findLatestOtpRequest(phone)
- markOtpUsed(requestId)
- findUserByPhone(phone)
- createUser(phone, role)
- updateUser(userId, updates)
- storeRefreshToken(userId, tokenHash, expiresAt)
- revokeRefreshToken(tokenHash)
- findRefreshToken(tokenHash)

**service.js** — Business logic:
- sendOtp(phone):
  1. Rate check: max 3 OTP requests per phone per 15min (check otp_requests table)
  2. Generate 6-digit OTP (crypto.randomInt)
  3. Hash OTP with bcrypt (cost 10)
  4. Store in otp_requests with 10min expiry
  5. Call SMS provider (stub function logOtp() for dev — console.log the OTP)
  6. Return { request_id, expires_in: 600 }
  
- verifyOtp(phone, otp, requestId):
  1. Find otp_request by id + phone
  2. Check not expired, not used, attempts < 5
  3. Increment attempts on each try
  4. bcrypt.compare(otp, hash)
  5. Mark as used on success
  6. Find or create user (role='customer' for new signups)
  7. Issue access + refresh tokens
  8. Store refresh token hash in Redis: rt:{userId}:{tokenId} TTL=30d
  9. Return { access_token, refresh_token, user: {id, phone, name, role} }

- refreshTokens(refreshToken):
  1. Verify JWT signature
  2. Check Redis for token existence (revocation check)
  3. Issue new access token + rotate refresh token
  4. Revoke old refresh token in Redis
  5. Return { access_token, refresh_token }

- logout(userId, refreshToken):
  1. Delete refresh token from Redis
  2. Add access token to Redis blocklist: bl:{jti} TTL=15m

**controller.js** — Thin controllers, call service:
- POST /api/auth/send-otp
- POST /api/auth/verify-otp
- POST /api/auth/refresh
- POST /api/auth/logout (requires auth middleware)
- GET  /api/auth/me (requires auth middleware) → return current user

**routes.js** — Express router, attach validators as middleware

### Create packages/api/src/middleware/auth.js:
- verifyAccessToken middleware:
  1. Extract Bearer token from Authorization header
  2. Check Redis blocklist for jti
  3. Verify JWT_SECRET
  4. Attach req.user = { userId, role, phone, city }
- requireRole(...roles) factory middleware — returns 403 if role not in list

### JWT payload shape:
{ sub: userId, role, phone, jti: uuid, iat, exp }

### Rate limiting (apply via middleware):
- sendOtp endpoint: 3 requests / 15 min / phone number (Redis counter)
- verifyOtp endpoint: 5 attempts / 15 min / phone number

### Register routes in app.js:
app.use('/api/auth', authRouter)

DELIVER: All files created. Test with curl:
1. POST /api/auth/send-otp { "phone": "9876543210" } → check console for OTP
2. POST /api/auth/verify-otp { phone, otp, request_id } → returns tokens
3. GET /api/auth/me with Bearer token → returns user
4. POST /api/auth/refresh → returns new tokens
```

---

## PHASE 3 — CATALOG SERVICE

---

### 🏪 CHUNK 4 — Catalog Service (Bakeries + Products)

```
Context: Auth is working. users table exists with role check.

## TASK: Build the full Catalog module — bakeries CRUD + products CRUD + menu endpoint.

### Create packages/api/src/modules/catalog/:

**validator.js** — Zod schemas:
- CreateBakeryDto: { name, description, address (object), city, lat, lng, operating_hours, max_daily_orders, advance_hours }
- UpdateBakeryDto: same fields all optional
- CreateProductDto: { name, description, base_price (positive number), category, is_customizable, customization_schema, images }
- UpdateProductDto: all optional
- ListBakeriesDto: { lat, lng, radius_km (default 10), q (optional search), page (default 1), limit (default 20) }

**repository.js**:
- createBakery(ownerId, data) → insert with ST_SetSRID(ST_MakePoint(lng,lat),4326) for location
- getBakeryById(id) → full row
- getBakeryBySlug(slug)
- updateBakery(id, data)
- listBakeriesByCity(city, lat, lng, radiusKm, search, page, limit):
  Use PostGIS: WHERE ST_DWithin(location, ST_SetSRID(ST_MakePoint($lng,$lat),4326)::geography, $radiusMeters)
  Include distance calculation: ST_Distance(location, ...) AS distance_meters
  ORDER BY distance_meters, rating DESC
- createProduct(bakeryId, data)
- getProductById(id)
- listProductsByBakery(bakeryId, includeUnavailable)
- updateProduct(id, data)
- deleteProduct(id) → soft delete (set is_available=false)
- getBakeryWithMenu(bakeryId) → bakery + all available products grouped by category

**service.js**:
- createBakery: generate slug from name (kebab-case + random suffix), call repo
- getBakeryMenu(bakeryId): use getBakeryWithMenu, cache result in Redis (key: menu:{bakeryId}, TTL: 300s)
- invalidateMenuCache(bakeryId): delete Redis key menu:{bakeryId}
- getAvailableTimeSlots(bakeryId, date):
  1. Get bakery operating_hours for that day
  2. Get count of existing orders for that date (from orders table)
  3. Generate 1-hour slots within operating hours
  4. Mark slots as full if orders >= max_daily_orders / available_slots
  5. Enforce advance_hours minimum lead time
  Return array of { slot_start, slot_end, available: bool, spots_left }

**controller.js**:
- POST /api/bakeries — requireRole('bakery_owner', 'admin')
- GET  /api/bakeries — public, supports ?lat&lng&radius_km&q&page&limit
- GET  /api/bakeries/:slug — public, returns bakery details
- PATCH /api/bakeries/:id — requireRole('bakery_owner') + ownership check
- GET  /api/bakeries/:id/menu — public, Redis-cached
- GET  /api/bakeries/:id/slots?date=YYYY-MM-DD — public
- POST /api/bakeries/:id/products — requireRole('bakery_owner') + ownership check
- PATCH /api/products/:id — requireRole('bakery_owner') + ownership check
- DELETE /api/products/:id — requireRole('bakery_owner') + ownership check

### Ownership check middleware:
Create canManageBakery middleware — verify req.user.userId matches bakery.owner_id

### Register routes in app.js

DELIVER: All files created. Test:
1. Create bakery as bakery_owner → returns bakery with slug
2. GET /api/bakeries?lat=23.02&lng=72.57&radius_km=10 → returns nearby bakeries
3. Add products to bakery
4. GET /api/bakeries/:id/menu → returns cached menu
5. GET /api/bakeries/:id/slots?date=2025-07-01 → returns time slots
```

---

## PHASE 4 — ORDER SERVICE

---

### 📦 CHUNK 5 — Order Service (State Machine)

```
Context: Catalog service is working with bakeries and products.

## TASK: Build the Order module — placement, state machine transitions, order history.

### Create packages/api/src/modules/orders/:

**constants.js** — Order state machine:
const ORDER_STATUS = {
  PENDING: 'pending',
  CONFIRMED: 'confirmed',
  PREPARING: 'preparing',
  READY: 'ready',
  ASSIGNED: 'assigned',
  PICKED: 'picked',
  DELIVERED: 'delivered',
  CANCELLED: 'cancelled',
  REFUND_REQUESTED: 'refund_requested',
  REFUNDED: 'refunded'
}

const ALLOWED_TRANSITIONS = {
  pending:    ['confirmed', 'cancelled'],
  confirmed:  ['preparing', 'cancelled'],
  preparing:  ['ready', 'cancelled'],
  ready:      ['assigned'],
  assigned:   ['picked', 'cancelled'],
  picked:     ['delivered'],
  delivered:  ['refund_requested'],
  refund_requested: ['refunded'],
}

**validator.js** — Zod schemas:
- PlaceOrderDto: {
    bakery_id: uuid,
    items: array of { product_id: uuid, quantity: positive int, customization: object optional },
    delivery_address: { line1, line2 optional, city, pincode, lat, lng },
    scheduled_at: ISO datetime string (must be future + advance_hours ahead),
    special_notes: string optional max 500,
    idempotency_key: uuid (client-generated)
  }
- UpdateOrderStatusDto: { status, reason optional }

**repository.js**:
- createOrder(data) → INSERT with RETURNING *
- getOrderById(id, includeItems=true)
- getOrdersByCustomer(customerId, page, limit)
- getOrdersByBakery(bakeryId, statuses, page, limit)
- updateOrderStatus(id, newStatus, extraData={}) → UPDATE + set updated_at
- getOrderCountForBakeryDate(bakeryId, date) — capacity check

**service.js**:

placeOrder(customerId, dto):
  1. Acquire Redis distributed lock: lock:order:{idempotency_key} (TTL 30s, use SET NX)
     - If lock exists: check if order with idempotency_key already exists → return existing
  2. Fetch bakery, validate is_active
  3. Validate scheduled_at >= NOW() + advance_hours
  4. Fetch each product, validate belongs to bakery + is_available
  5. Calculate subtotal (sum of base_price * qty + customization upcharge)
  6. Calculate platform_fee = subtotal * PLATFORM_FEE_PERCENT / 100
  7. Calculate delivery_fee (flat ₹40 for now, distance-based later)
  8. Check daily capacity: getOrderCountForBakeryDate vs max_daily_orders
  9. Create Razorpay order (call razorpay service — see Chunk 6)
  10. INSERT order (status=pending, razorpay_order_id set)
  11. Release Redis lock
  12. Return { order, razorpay_order_id, razorpay_key_id }

transitionOrderStatus(orderId, newStatus, actorId, actorRole, reason):
  1. Fetch current order
  2. Validate actor has permission for this transition:
     - customer can: cancel (from pending/confirmed)
     - bakery_owner can: confirmed→preparing, preparing→ready
     - agent can: assigned→picked, picked→delivered
     - system/admin can: any
  3. Check ALLOWED_TRANSITIONS[currentStatus] includes newStatus
  4. UPDATE order status
  5. Publish internal event for downstream (notification, delivery assignment)
  6. Return updated order

getCustomerOrders(customerId, page):
  Return paginated orders with bakery name + first item name

**controller.js**:
- POST /api/orders — requireAuth
  Rate limit: 5 orders / 1 min per user (Redis counter)
- GET  /api/orders — requireAuth (customer sees own, bakery_owner sees bakery orders)
- GET  /api/orders/:id — requireAuth + ownership check (customer or bakery or agent)
- PATCH /api/orders/:id/status — requireAuth
- POST /api/orders/:id/cancel — requireAuth (shortcut for cancel transition)
- POST /api/orders/:id/rate — requireAuth (customer only, after delivered)

### Ownership check for orders:
Customer can only see their own orders.
Bakery owner can only see orders for their bakery.
Agent can only see their assigned orders.

DELIVER: All files created. Test:
1. Place order as customer → returns Razorpay order_id (Razorpay stub OK)
2. Attempt duplicate order with same idempotency_key → returns same order
3. Transition order status: pending→confirmed as bakery_owner
4. Attempt invalid transition (e.g. pending→delivered) → returns 400 with clear error
5. GET /api/orders?page=1 as customer → paginated list
```

---

## PHASE 5 — PAYMENT SERVICE

---

### 💳 CHUNK 6 — Payment Service (Razorpay Integration)

```
Context: Order service places orders with status=pending + razorpay_order_id.

## TASK: Build the Payment module — Razorpay order creation, webhook verification, payment events ledger.

### Install: razorpay npm package

### Create packages/api/src/modules/payments/:

**validator.js** — Zod schemas:
- CreateRazorpayOrderDto: { order_id: uuid }
- RazorpayWebhookDto: raw body (do NOT parse before signature check)
- VerifyPaymentDto: { razorpay_order_id, razorpay_payment_id, razorpay_signature }

**repository.js**:
- insertPaymentEvent(orderId, eventType, amount, gatewayRef, metadata)
  — append-only, NEVER update
- getPaymentEventsByOrder(orderId) → full payment history
- getLatestPaymentEvent(orderId)

**service.js**:

createRazorpayOrder(amountPaise, currency='INR', receipt, notes={}):
  - Use Razorpay SDK: razorpay.orders.create(...)
  - Return { id, amount, currency }

verifyWebhookSignature(rawBody, signature):
  - HMAC-SHA256: crypto.createHmac('sha256', RAZORPAY_WEBHOOK_SECRET).update(rawBody).digest('hex')
  - Constant-time comparison to prevent timing attacks (crypto.timingSafeEqual)
  - Throw if invalid

processWebhookEvent(event, orderId):
  Handle these Razorpay webhook events:
  
  'payment.captured':
    1. Insert payment_event (type=captured, amount, gateway_ref=payment_id)
    2. Update order: payment_status=captured
    3. Transition order status: pending → confirmed (call order service)
    4. Trigger notification (stub for now: console.log)
  
  'payment.failed':
    1. Insert payment_event (type=failed)
    2. Update order: payment_status=failed
    3. Transition order → cancelled
    4. Trigger notification
  
  'refund.created':
    1. Insert payment_event (type=refunded, amount=refund amount)
    2. Transition order → refunded

verifyClientPayment(razorpayOrderId, paymentId, signature):
  - Client-side verification (after Razorpay checkout callback)
  - HMAC: razorpay_order_id + "|" + razorpay_payment_id
  - Returns bool

getOrderPaymentSummary(orderId):
  - Returns { subtotal, platform_fee, delivery_fee, total, payment_status, events }

**controller.js**:
- POST /api/payments/webhook
  CRITICAL: Use express.raw({ type: '*/*' }) on this route ONLY (not express.json)
  Extract raw body for signature verification
  Verify signature FIRST — return 400 immediately if invalid
  Process event asynchronously (don't block webhook response)
  Always return 200 to Razorpay (else retries)

- POST /api/payments/verify — requireAuth
  Client calls this after Razorpay checkout succeeds
  Verify payment signature
  Return { verified: true, order }

- GET /api/payments/orders/:orderId — requireAuth + ownership check

### Integration with order service:
Update placeOrder() in order service to call createRazorpayOrder and store razorpay_order_id

### Idempotency:
Before inserting payment_event, check if event with same gateway_ref already exists
(Razorpay retries webhooks — handle gracefully)

DELIVER: All files created. Test with Razorpay test mode:
1. Place order → receive razorpay_order_id
2. Simulate webhook: POST /api/payments/webhook with test payload + valid HMAC
3. Order status changes to confirmed
4. payment_events table has 1 row
5. Replay same webhook → idempotent, no duplicate event inserted
```

---

## PHASE 6 — DELIVERY & TRACKING

---

### 🚴 CHUNK 7 — Delivery Assignment Service

```
Context: Orders can reach 'ready' status. Agents exist as users with role='agent'.

## TASK: Build the Delivery module — agent availability, order assignment, pickup code validation, delivery milestones.

### Create packages/api/src/modules/delivery/:

**validator.js**:
- UpdateAgentStatusDto: { status: enum('available','busy','offline') }
- ConfirmPickupDto: { pickup_code: string 4-digit }
- UpdateDeliveryStatusDto: { status: enum('en_route_bakery','at_bakery','en_route_customer','delivered') }

**repository.js**:
- setAgentAvailability(agentId, status) → Redis SETEX agent:status:{agentId} TTL=300s
- getAvailableAgents(city) → scan Redis keys (or maintain a sorted set of available agents)
- createDeliveryAssignment(orderId, agentId, pickupCode, agentFee)
- getAssignmentByOrderId(orderId)
- getAssignmentByAgent(agentId, status)
- updateAssignmentStatus(assignmentId, status, timestamp)

**service.js**:

assignDeliveryAgent(orderId):
  Called automatically when order transitions to 'ready'
  1. Get order details (delivery_location, bakery location)
  2. Get list of available agents from Redis (agent:status:{agentId} = 'available')
  3. Get each agent's current location from Redis (agent:loc:{agentId})
  4. Select nearest available agent (Haversine formula using last known location)
  5. If no agent available: retry after 60s (simple setTimeout for now), notify bakery
  6. Generate 4-digit pickup code
  7. Calculate agent_fee (₹30 base + ₹5 per km)
  8. createDeliveryAssignment(...)
  9. Transition order: ready → assigned
  10. Update agent status: available → busy in Redis
  11. Return assignment

confirmPickup(agentId, orderId, pickupCode):
  1. Get assignment
  2. Verify agentId matches assignment.agent_id
  3. Verify pickupCode matches assignment.pickup_code
  4. If codes match: transition assignment: at_bakery → en_route_customer
  5. Transition order: assigned → picked
  6. Set assignment.picked_at = NOW()
  7. Return { confirmed: true }

confirmDelivery(agentId, orderId):
  1. Verify assignment
  2. Transition assignment → delivered
  3. Transition order: picked → delivered
  4. Set assignment.delivered_at = NOW()
  5. Update agent status → available in Redis
  6. Trigger post-delivery flow (rating request notification — stub)

getAgentEarnings(agentId, startDate, endDate):
  Sum agent_fee from completed delivery_assignments in date range

**controller.js**:
- PUT  /api/agent/status — requireRole('agent')
- GET  /api/agent/assignment — requireRole('agent') → current active assignment
- POST /api/agent/pickup-confirm — requireRole('agent') { order_id, pickup_code }
- POST /api/agent/delivery-confirm — requireRole('agent') { order_id }
- GET  /api/agent/earnings — requireRole('agent')
- GET  /api/vendor/orders/:id/assignment — requireRole('bakery_owner') → see assigned agent

### Auto-assignment trigger:
In order service transitionOrderStatus(), when newStatus === 'ready':
  import deliveryService and call assignDeliveryAgent(orderId) asynchronously

DELIVER: All files created. Test:
1. Set agent status → available
2. Transition order to 'ready' → assignment auto-created
3. Agent gets assignment via GET /api/agent/assignment
4. POST pickup-confirm with correct code → order status → 'picked'
5. POST delivery-confirm → order status → 'delivered', agent → available
```

---

### 📡 CHUNK 8 — Real-Time Tracking (WebSocket + MongoDB)

```
Context: Delivery assignments exist. Agents are actively delivering orders.

## TASK: Build the real-time tracking system — GPS ingestion, MongoDB persistence, WebSocket push to customers.

### Install in packages/api: ws

### Create packages/api/src/modules/tracking/:

**mongoSchema.js** — Mongoose schemas:
TrackingEvent schema:
{
  agent_id: String,        // UUID
  order_id: String,        // UUID
  location: {
    type: { type: String, default: 'Point' },
    coordinates: [Number]  // [lng, lat]
  },
  status: String,
  speed_kmh: Number,
  bearing: Number,
  battery_level: Number,
  timestamp: { type: Date, default: Date.now, index: true }
}
Indexes: { agent_id: 1, timestamp: -1 }, { order_id: 1, timestamp: -1 }
TTL index: expires after 90 days (expireAfterSeconds: 7776000)
2dsphere index on location field

**validator.js**:
- UpdateLocationDto: {
    order_id: uuid,
    lat: number min(-90) max(90),
    lng: number min(-180) max(180),
    speed_kmh: number optional,
    bearing: number 0-360 optional,
    battery: number 0-100 optional
  }

**repository.js**:
- saveTrackingEvent(agentId, orderId, locationData) → insert MongoDB document
- getLatestAgentLocation(agentId) → Redis GET agent:loc:{agentId}
- setAgentLocation(agentId, lat, lng) → Redis SETEX agent:loc:{agentId} JSON TTL=60s
- getTrackingHistory(orderId, limit=50) → MongoDB query sorted by timestamp DESC

**service.js**:

updateAgentLocation(agentId, dto):
  1. Validate agent has an active delivery for dto.order_id
  2. Save to MongoDB (async, fire-and-forget — don't await)
  3. Set Redis: agent:loc:{agentId} = {lat, lng, updated_at} SETEX 60s
  4. Calculate ETA (simple: remaining_distance / avg_speed, or Google Maps stub)
  5. Publish to Redis Pub/Sub channel: tracking:{order_id}
     Payload: { lat, lng, bearing, speed_kmh, status, eta_minutes, updated_at }
  6. Rate limit: max 30 location updates / min per agent (Redis counter)
  7. Return { ok: true, next_checkpoint }

getOrderTracking(orderId, requestingUserId):
  1. Verify user is customer of this order OR the assigned agent
  2. Get latest location from Redis
  3. Get assignment status
  4. Calculate ETA
  5. Return { lat, lng, status, eta_minutes, agent: { name }, updated_at }

### WebSocket server (packages/api/src/ws/trackingServer.js):
- Attach to the same HTTP server (server.on('upgrade', ...))
- Path: /ws/track/:order_id
- On connection:
  1. Parse order_id from URL
  2. Verify JWT from query param: ?token=xxx
  3. Verify user is authorized for this order
  4. Subscribe to Redis Pub/Sub: tracking:{order_id}
  5. Send initial tracking state immediately
  6. Forward Redis Pub/Sub messages to this WebSocket
  7. On close: unsubscribe from Redis Pub/Sub
- Heartbeat: ping every 30s, close if no pong in 10s
- Error handling: catch all errors, close connection gracefully

### Update packages/api/src/app.js:
- Create HTTP server: const server = http.createServer(app)
- Attach WebSocket server to HTTP server
- Export server instead of app

**controller.js**:
- POST /api/tracking/location — requireRole('agent') — rate limited
- GET  /api/tracking/:order_id — requireAuth (customer or agent)
- GET  /api/tracking/:order_id/history — requireAuth (admin/agent)

DELIVER: All files created. Test:
1. Agent POSTs location update → saved to MongoDB + Redis updated
2. GET /api/tracking/:order_id → returns latest location with ETA
3. Open WebSocket connection to /ws/track/:order_id?token=xxx → receives initial state
4. POST another location update → WebSocket client receives push event within 1s
5. MongoDB tracking_events collection has documents with TTL index
```

---

## PHASE 7 — NOTIFICATIONS

---

### 🔔 CHUNK 9 — Notification Service (In-Process Event System)

```
Context: Orders, payments, delivery all working. Need to notify users at key events.

## TASK: Build a lightweight in-process notification system using EventEmitter (no Kafka needed at launch).

### Create packages/api/src/lib/eventBus.js:
- Simple Node.js EventEmitter singleton
- Used by all services to emit domain events
- Consumers register handlers at startup

### Create packages/api/src/modules/notifications/:

**events.js** — Event constants:
ORDER_PLACED, ORDER_CONFIRMED, ORDER_PREPARING, ORDER_READY,
ORDER_ASSIGNED, ORDER_PICKED, ORDER_DELIVERED, ORDER_CANCELLED,
PAYMENT_FAILED, DELIVERY_ASSIGNED, OTP_SENT

**templates.js** — Notification templates by event:
Each event maps to: { title, body } templates for push/SMS
Examples:
ORDER_CONFIRMED: {
  customer: { title: "Order Confirmed! 🎂", body: "Your order from {bakery_name} is confirmed. Ready by {scheduled_time}" },
  bakery: { title: "New Order #BR{order_short_id}", body: "Prepare {item_count} item(s) by {scheduled_time}" }
}

**channels.js** — Notification delivery stubs:
sendPush(userId, title, body, data={}):
  1. Get user's fcm_token from DB
  2. Call Firebase FCM API (stub: console.log in dev)
  
sendSMS(phone, message):
  Stub: console.log in dev, Exotel/MSG91 in production
  
sendEmail(to, subject, html):
  Stub: console.log in dev, AWS SES in production

**service.js**:
notify(userId, channel, eventType, templateData):
  1. Get template for event
  2. Interpolate templateData into template strings
  3. Call appropriate channel (push, sms, email)
  4. Log notification (console.log in dev with structured format)

**handlers.js** — Event handlers registered on eventBus:
On ORDER_CONFIRMED:
  - notify customer (push + SMS)
  - notify bakery_owner (push)
On ORDER_PREPARING:
  - notify customer (push)
On ORDER_READY:
  - notify admin/system (internal) — triggers delivery assignment
On ORDER_ASSIGNED:
  - notify customer with agent name (push)
  - notify agent (push)
On ORDER_PICKED:
  - notify customer (push)
On ORDER_DELIVERED:
  - notify customer with rating prompt (push)
  - notify bakery (push)
On ORDER_CANCELLED:
  - notify customer + bakery (push + SMS)
On PAYMENT_FAILED:
  - notify customer (push + SMS)

### Wire up:
In app.js, import and register all notification handlers:
  import './modules/notifications/handlers.js'

In order service, delivery service, payment service:
  import { eventBus } from '../lib/eventBus.js'
  eventBus.emit(ORDER_CONFIRMED, { orderId, customerId, bakeryId, bakeryName, ... })

DELIVER: All files created. Test:
1. Place + confirm an order → console shows structured notification logs for customer and bakery
2. Transition order through all states → notification logs appear at each milestone
3. Simulate payment failure → failure notification logged
```

---

## PHASE 8 — CUSTOMER WEB APP

---

### 🌐 CHUNK 10 — Customer Web App: Browse, Search & Bakery Menu

```
Context: Backend API is fully functional. Starting customer-facing React app.

## TASK: Build the customer web app browse/search experience — homepage, bakery listing, bakery detail + menu page.

Working directory: packages/web/

### Tech: React + Vite (plain JS), React Router v6, Zustand, Axios, Tailwind CSS

### Install: tailwindcss, @tailwindcss/vite, axios, react-router-dom, zustand, react-hot-toast, lucide-react, date-fns

### App structure to create:
src/
├── api/
│   ├── client.js       # Axios instance with base URL, auth interceptors
│   └── endpoints.js    # All API call functions (no inline fetch anywhere)
├── stores/
│   ├── authStore.js    # Zustand: user, tokens, login/logout actions
│   └── cartStore.js    # Zustand: cart items, add/remove/clear
├── pages/
│   ├── HomePage.jsx
│   ├── SearchPage.jsx
│   ├── BakeryPage.jsx       # Bakery detail + menu
│   ├── LoginPage.jsx
│   └── NotFoundPage.jsx
├── components/
│   ├── layout/
│   │   ├── Header.jsx
│   │   └── BottomNav.jsx    # Mobile bottom navigation
│   ├── bakery/
│   │   ├── BakeryCard.jsx
│   │   ├── BakeryGrid.jsx
│   │   └── ProductCard.jsx
│   ├── common/
│   │   ├── Spinner.jsx
│   │   ├── SkeletonCard.jsx
│   │   └── ErrorBoundary.jsx
│   └── cart/
│       └── CartDrawer.jsx
├── hooks/
│   ├── useGeolocation.js    # Get user's lat/lng
│   └── useDebounce.js
└── App.jsx

### Design system — Brand colors for BakeRoute:
Primary: #FF6B35 (warm orange — bakery feel)
Secondary: #FFF3E0 (cream)
Accent: #4CAF50 (success/available)
Neutral dark: #1A1A2E
Font: Inter (Google Fonts)

### pages/HomePage.jsx:
- Use useGeolocation to get user location on mount
- Fetch nearby bakeries: GET /api/bakeries?lat&lng&radius_km=10
- Show location permission prompt if denied
- Hero section with search bar (debounced, navigates to /search?q=)
- "Popular Near You" horizontal scroll (top 6 bakeries sorted by rating)
- "All Bakeries" grid below
- Each bakery shows: cover image, name, rating, distance, estimated delivery time
- Skeleton cards while loading

### pages/SearchPage.jsx:
- Read q param from URL
- Real-time search: GET /api/bakeries?q={query}&lat&lng&radius_km=15
- Debounced at 300ms
- Filter chips: All | Cakes | Pastry | Bread
- Sort options: Nearest | Rating | Popular
- Show "No bakeries found" empty state with illustration

### pages/BakeryPage.jsx (route: /bakery/:slug):
- Fetch bakery menu: GET /api/bakeries/:id/menu
- Sticky bakery header: image, name, rating, operating hours badge (Open/Closed)
- Horizontal category tabs (Cakes, Pastry, etc.) — smooth scroll to section
- ProductCard for each item: image, name, description, price, "Add to Cart" button
- Customizable products show "Customize" button instead of direct add
- Floating cart summary bar at bottom when cart has items

### components/cart/CartDrawer.jsx:
- Slide-in drawer from right
- Shows each item, quantity +/- controls, customization summary
- Running total
- "Schedule & Checkout" CTA button (navigates to /checkout)

### api/client.js:
- Axios instance with baseURL from VITE_API_URL env var
- Request interceptor: attach Bearer token from authStore
- Response interceptor: on 401 → call refresh token → retry original request
- On refresh failure → logout + redirect to /login

DELIVER: All pages created and styled. 
npm run dev in packages/web must show:
1. Homepage with bakery grid (uses real API data)
2. Search with live filtering
3. Bakery menu page with category tabs
4. Cart drawer opens and tracks items
5. Mobile-responsive (test at 390px width)
```

---

### 🛒 CHUNK 11 — Customer Web App: Checkout, Order Placement + AI Cake Preview

```
Context: Customer can browse bakeries and add items to cart.

## TASK: Build the checkout flow — delivery address, time slot selection, customization modal, Razorpay payment, AI cake preview.

### Create in packages/web/src/:

**pages/CheckoutPage.jsx** (route: /checkout):
Multi-step form — 3 steps with progress indicator:

Step 1 — Delivery Details:
- Delivery address form (line1, line2, city, pincode)
- Map picker (simple lat/lng from browser geolocation + manual input — no Google Maps SDK yet)
- Special notes textarea
- Validate all required fields before Next

Step 2 — Schedule Delivery:
- Date picker (min date: today + bakery.advance_hours, max: 14 days ahead)
- On date select: fetch GET /api/bakeries/:id/slots?date=YYYY-MM-DD
- Display time slots as clickable cards: "2:00 PM - 3:00 PM" with available/full indicator
- Disabled state for full slots
- Highlight selected slot

Step 3 — Review & Pay:
- Order summary: bakery name, items + quantities, customizations
- Price breakdown: subtotal, delivery fee, platform fee, total
- Idempotency key: generate UUID on page mount (NOT on each render)
- "Place Order & Pay" button → calls POST /api/orders → receives { razorpay_order_id }
- Opens Razorpay checkout modal (load Razorpay script dynamically)
- On payment success: POST /api/payments/verify
- On success: navigate to /orders/:id with success toast
- On payment failure: show retry option, do NOT create duplicate order (same idempotency_key)

**components/product/CustomizationModal.jsx**:
- Opens when user clicks "Customize" on a customizable product
- Reads product.customization_schema to render dynamic form fields:
  - flavors → radio buttons (Chocolate, Vanilla, Red Velvet...)
  - tiers → number input (1-5)
  - message → text input max 60 chars (live preview of text)
  - design_styles → image grid select
- "Preview Cake with AI" button → POST /api/ai/cake-preview (async)
- Show loading state while AI generates (animated cake illustration placeholder)
- Display AI-generated preview image when ready (poll GET /api/ai/cake-preview/:jobId every 3s)
- "Add to Cart with Customization" button

**pages/AiPreviewPage.jsx** (accessible from customization modal):
- Full-screen preview of AI-generated cake image
- Customization summary alongside
- "Use This Design" + "Regenerate" buttons
- "Download Preview" option

### Create packages/api/src/modules/ai/:
**service.js**:
- generateCakePreview(userId, { bakeryId, theme, text, style, flavor, tiers }):
  1. Rate limit: 10 previews / 1 hour per user (Redis counter)
  2. Build structured prompt: "Professional bakery cake photograph, {theme} theme, {flavor} flavored, {tiers} tier cake with '{text}' written in {style} frosting. Studio lighting, white background, hyper-realistic food photography."
  3. Call OpenAI DALL-E 3 API (model: dall-e-3, size: 1024x1024, quality: standard)
  4. Store result URL + job metadata in Redis: ai_preview:{jobId} TTL=1h
  5. Return { job_id, status: 'completed', preview_url }
  Note: For V1 — call synchronously (async Kafka queue is Phase 2)

**controller.js**:
- POST /api/ai/cake-preview — requireAuth
- GET  /api/ai/cake-preview/:jobId — requireAuth (poll endpoint)

### Razorpay integration in frontend:
Load Razorpay checkout script on demand (not in index.html):
const script = document.createElement('script')
script.src = 'https://checkout.razorpay.com/v1/checkout.js'
Options: key, amount (paise), order_id, name: 'BakeRoute', theme: { color: '#FF6B35' }
handler: (response) => verifyPayment(response)

DELIVER: All pages and components created. Test complete flow:
1. Add items to cart (including 1 customizable item)
2. Open customization modal → fill options → click AI Preview → see preview
3. Complete all 3 checkout steps
4. Razorpay test card payment (use Razorpay test card: 4111...)
5. On success → navigate to order confirmation page with order ID
```

---

### 📍 CHUNK 12 — Customer Web App: Order History + Real-Time Tracking UI

```
Context: Customer can place orders. Orders reach 'assigned' state with a delivery agent.

## TASK: Build the order history page and live tracking UI with WebSocket.

### Create in packages/web/src/:

**pages/OrdersPage.jsx** (route: /orders):
- Fetch GET /api/orders → paginated list
- Tabs: Active (pending/confirmed/preparing/ready/assigned/picked) | Past (delivered/cancelled)
- OrderListItem component: bakery name, date, status badge, item count, total, "Track" button
- Re-order button for past orders (pre-fills cart with same items)
- Infinite scroll or "Load More" pagination
- Status badge colors:
  pending → gray, confirmed → blue, preparing → orange, 
  ready → yellow, assigned/picked → purple, delivered → green, cancelled → red

**pages/OrderDetailPage.jsx** (route: /orders/:id):
- Order details: bakery info, items list, customization, price breakdown
- Status timeline component (vertical stepper)
- For active deliveries: "Track Live" button → opens TrackingMap
- Rating section (shown after delivered, if not yet rated)
  - Star rating for bakery (1-5)
  - Star rating for agent (1-5)
  - Optional review text
  - Submit: POST /api/orders/:id/rate

**components/tracking/TrackingMap.jsx**:
- Full-screen overlay (modal) with live map
- Use Leaflet.js (free, no API key) for map rendering: install leaflet, react-leaflet
- Map centered on delivery address, shows:
  - Blue pin: customer delivery address
  - Red pin: bakery location
  - Orange moving pin: agent's live location (updates via WebSocket)
  - Dashed route line between agent and customer
- Status banner at top: "Agent is on the way · ETA 12 mins"
- Agent name + phone (tap to call)
- Order status updates in real-time

**hooks/useOrderTracking.js**:
WebSocket connection management:
- Connect to /ws/track/:order_id?token={accessToken} on mount
- Handle reconnection on disconnect (exponential backoff: 1s, 2s, 4s, 8s, max 30s)
- Parse incoming messages: { lat, lng, bearing, status, eta_minutes }
- Update local state: { agentLocation, status, eta }
- Close WebSocket on component unmount
- Expose: { agentLocation, status, eta, connected, error }

**components/tracking/AgentPin.jsx**:
- Animated Leaflet marker for agent
- Rotates based on bearing angle
- Smooth position transitions (CSS transition on translate)
- Shows agent's initials in circle

DELIVER: All components created. Test:
1. GET /orders → shows list with correct status badges
2. Click Track → map opens with Leaflet
3. Agent posts location update → map pin moves smoothly
4. WebSocket disconnects → auto-reconnects → resumes tracking
5. Order delivered → show rating prompt
6. Submit rating → stars saved to DB
```

---

## PHASE 9 — VENDOR DASHBOARD

---

### 🏭 CHUNK 13 — Bakery Vendor Dashboard

```
Context: Full order lifecycle is working. Now build the vendor-facing React app.

Working directory: packages/vendor/

## TASK: Build the bakery vendor dashboard — order management, menu management, analytics.

### Install same as packages/web (Tailwind, Zustand, Axios, react-router-dom, lucide-react, recharts)

### Pages to create:

**pages/DashboardPage.jsx** (route: /):
- Today's summary cards: Orders Today, Revenue Today, Pending Orders, Avg Prep Time
- Real-time new order notification (poll GET /api/vendor/orders?status=pending every 10s)
  OR WebSocket (add a vendor-notifications WS endpoint — /ws/vendor/:bakeryId)
- Audio alert on new order (play beep sound)

**pages/LiveOrdersPage.jsx** (route: /orders):
- Kanban board layout — columns: Pending | Confirmed | Preparing | Ready
- Each order card: order ID, customer name (first name only), items summary, scheduled time, total
- Action buttons per column:
  Pending → "Accept" (→ confirmed) | "Reject" (→ cancelled)
  Confirmed → "Start Preparing" (→ preparing)
  Preparing → "Mark Ready" (→ ready)
- Real-time updates (poll every 10s)
- Order detail modal: full items list, customization details, delivery address, special notes
- Late orders highlight in red (scheduled_at < NOW() and not yet ready)

**pages/MenuPage.jsx** (route: /menu):
- List all products grouped by category
- Toggle product availability (PATCH /api/products/:id { is_available })
- Add new product button → opens ProductFormModal
- Edit product → opens ProductFormModal with prefilled data
- ProductFormModal:
  - All product fields (name, description, base_price, category, is_customizable)
  - Customization schema builder:
    If is_customizable = true, show:
    - Add flavors (tag input)
    - Max tiers (number)
    - Enable custom message (toggle)
    - Add design styles (tag input)
  - Image URL fields (up to 5)

**pages/AnalyticsPage.jsx** (route: /analytics):
- Date range picker (default: last 7 days)
- Charts using Recharts:
  - Revenue trend: LineChart (daily revenue)
  - Orders by status: PieChart (completed vs cancelled)
  - Popular products: BarChart (top 5 by order count)
  - Avg prep time trend: AreaChart
- Data source: GET /api/vendor/analytics?start=&end=

### Create packages/api/src/modules/vendor/:
**controller.js**:
- GET  /api/vendor/orders — requireRole('bakery_owner') — filtered by bakery + optional status
- GET  /api/vendor/orders/:id — order detail with customization
- PUT  /api/vendor/orders/:id/status — accept/prepare/ready transitions
- GET  /api/vendor/analytics — requireRole('bakery_owner')
  Query: orders + payment_events for bakery in date range
  Return: daily_revenue[], order_counts{}, popular_products[], avg_prep_time_minutes
- GET  /api/vendor/capacity — today's order count vs max_daily_orders
- PUT  /api/vendor/settings — update bakery settings (hours, capacity, advance_hours)

### Vendor auth flow:
- Login via same OTP system
- Role check: if user.role !== 'bakery_owner' → redirect to customer app
- Vendor app runs on different port/subdomain: localhost:5174

DELIVER: Vendor app created. Test:
1. Login as bakery_owner → lands on dashboard
2. New order in DB → appears in "Pending" column within 10s
3. Accept order → moves to Confirmed column
4. Mark through stages → order moves across kanban
5. Analytics page shows charts with real data
6. Toggle product availability → reflects in customer menu within cache TTL
```

---

## PHASE 10 — AGENT PWA

---

### 🛵 CHUNK 14 — Delivery Agent Progressive Web App

```
Context: Delivery assignment service assigns orders to agents.

Working directory: packages/agent/

## TASK: Build the delivery agent PWA — assignment view, navigation, GPS location posting, fragile cargo checklist.

### Install: leaflet, react-leaflet (for map), vite-plugin-pwa (for PWA manifest)

### Configure as PWA:
- vite.config.js: add VitePWA plugin
- manifest: name: BakeRoute Agent, icons, theme_color: #FF6B35
- Service worker: offline fallback page, cache API responses for 5 min

### Pages to create:

**pages/StatusPage.jsx** (route: / when no active delivery):
- Agent status toggle: AVAILABLE | BUSY | OFFLINE
  - Large prominent button with color (green/orange/gray)
  - PATCH /api/agent/status on toggle
- Today's stats: Deliveries completed, Earnings today
- Last 5 deliveries list

**pages/DeliveryPage.jsx** (route: /delivery — shown when assignment exists):
On mount: GET /api/agent/assignment → shows current delivery

Section 1 — Pickup (if status=assigned/en_route_bakery/at_bakery):
  - Bakery name, address
  - "Navigate to Bakery" button → opens Google Maps in new tab with bakery coordinates
  - Status buttons: "On My Way" | "Arrived at Bakery"
  - Fragile Cargo Checklist (must confirm before pickup):
    ☐ Packaging is secure and sealed
    ☐ Cake box is upright and level
    ☐ Thermal bag used for temperature-sensitive items
    ☐ Customer name verified on box
  - All checklist items must be checked before "Enter Pickup Code" appears
  - Pickup code input (4-digit) → POST /api/agent/pickup-confirm

Section 2 — Delivery (if status=en_route_customer/picked):
  - Customer address
  - "Navigate to Customer" button → Google Maps
  - Delivery status: "Arrived at Customer" button
  - "Confirm Delivery" button → POST /api/agent/delivery-confirm

**hooks/useLocationTracking.js**:
- Start GPS tracking when agent has active delivery
- Use navigator.geolocation.watchPosition() with high accuracy
- Post to POST /api/tracking/location every 5 seconds
- Throttle: only post if position changed > 10 meters (reduce unnecessary API calls)
- Stop tracking after delivery confirmed
- Handle permission denied gracefully
- Battery optimization: reduce frequency to 15s if battery < 20%

**components/MapView.jsx**:
- Leaflet map showing:
  - Agent's current position (blue dot)
  - Destination pin (bakery OR customer depending on stage)
  - Simple line between them

**pages/EarningsPage.jsx** (route: /earnings):
- This week / This month / All time toggle
- Total earnings, number of deliveries, avg per delivery
- List of recent deliveries with earnings
- Data from GET /api/agent/earnings

DELIVER: Agent PWA created. Test:
1. Login as agent → see status toggle
2. Set status to available
3. Create a test order and transition to 'ready' → assignment created
4. Agent sees assignment on DeliveryPage
5. GPS tracking starts → location updates visible in MongoDB
6. Complete fragile checklist → pickup code input appears
7. Enter correct code → status updates
8. Confirm delivery → agent returns to StatusPage
9. Install as PWA on mobile (add to home screen)
```

---

## PHASE 11 — CI/CD & PRODUCTION SETUP

---

### 🚀 CHUNK 15 — CI/CD Pipeline + Production Checklist

```
Context: Full application is built and working locally.

## TASK: Set up GitHub Actions CI, Dockerfiles, production environment configuration, and health monitoring.

### Create Dockerfile for packages/api:
- Base: node:20-alpine
- Multi-stage: builder + runner
- Non-root user (uid 1001)
- COPY only production dependencies
- Expose port 4000
- CMD: node src/app.js (NOT nodemon)
- Add .dockerignore (node_modules, .env, tests, docs)

### Create Dockerfile for packages/web, packages/vendor, packages/agent:
- Stage 1 (builder): node:20-alpine, npm ci, npm run build
- Stage 2 (runner): nginx:alpine, COPY --from=builder /app/dist /usr/share/nginx/html
- COPY nginx.conf (SPA routing: try_files $uri $uri/ /index.html)
- Expose 80

### Create .github/workflows/ci.yml:
name: CI
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test-api:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env: { POSTGRES_PASSWORD: test, POSTGRES_DB: bakeroute_test }
        ports: ['5432:5432']
      redis:
        image: redis:7
        ports: ['6379:6379']
      mongo:
        image: mongo:7
        ports: ['27017:27017']
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20, cache: npm }
      - run: npm ci
      - run: npm run lint --workspace=packages/api
      - run: npm test --workspace=packages/api
        env:
          DATABASE_URL: postgresql://postgres:test@localhost:5432/bakeroute_test
          REDIS_URL: redis://localhost:6379
          MONGODB_URL: mongodb://localhost:27017/bakeroute_test
          JWT_SECRET: test-secret-minimum-32-chars-long!!
          JWT_REFRESH_SECRET: test-refresh-secret-min-32-chars!
          NODE_ENV: test

  build-docker:
    needs: test-api
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - name: Build API image
        run: docker build -t bakeroute-api:${{ github.sha }} packages/api/
      - name: Build Web image
        run: docker build -t bakeroute-web:${{ github.sha }} packages/web/

### Create packages/api/src/__tests__/ with integration tests:

**auth.test.js**: (using supertest + jest)
- POST /api/auth/send-otp with valid phone → 200 + request_id
- POST /api/auth/send-otp rate limit → 429 after 3 requests
- POST /api/auth/verify-otp with wrong OTP → 401
- Full flow: send OTP → get OTP from DB → verify → receive tokens → GET /api/auth/me

**orders.test.js**:
- Place order with valid cart → 200 + razorpay_order_id
- Duplicate idempotency_key → same order returned (idempotent)
- Invalid transition → 400

### Create packages/api/src/routes/health.js:
GET /healthz:
  - Check PostgreSQL: SELECT 1
  - Check Redis: PING
  - Check MongoDB: db.admin().ping()
  - Return 200 { status: 'ok', pg: 'ok', redis: 'ok', mongo: 'ok', uptime: process.uptime() }
  - Return 503 if any dependency fails

### Production environment checklist file: docs/PRODUCTION_CHECKLIST.md
Create checklist covering:
☐ All env vars set in production (never .env files)
☐ NODE_ENV=production
☐ JWT_SECRET is cryptographically random (min 64 chars)
☐ PostgreSQL: SSL mode required, connection pool 10-20
☐ Redis: AUTH password set, MAXMEMORY policy=allkeys-lru
☐ MongoDB: auth enabled, IP whitelist
☐ Razorpay: LIVE keys (not test)
☐ /healthz returns 200
☐ CORS origins: only production domains
☐ Rate limits configured
☐ Helmet.js headers verified (check with securityheaders.com)
☐ HTTPS only (redirect HTTP → HTTPS at nginx level)
☐ Backup strategy confirmed (daily RDS snapshots)
☐ Error monitoring: Sentry DSN configured

### Update tasks/todo.md — mark all chunks complete

DELIVER: All CI/CD files created.
1. GitHub Actions workflow YAML is valid (no syntax errors — verify with actionlint or yamllint)
2. Integration tests pass locally: npm test --workspace=packages/api
3. Docker build succeeds: docker build -t bakeroute-api packages/api/
4. /healthz returns 200 with all services connected
5. Production checklist exists at docs/PRODUCTION_CHECKLIST.md
```

---

## CHUNK DEPENDENCY MAP

```
Chunk 1 (Foundation)
    └─→ Chunk 2 (DB Schema)
            └─→ Chunk 3 (Auth)
                    └─→ Chunk 4 (Catalog)
                            └─→ Chunk 5 (Orders)
                                    ├─→ Chunk 6 (Payments)
                                    └─→ Chunk 7 (Delivery)
                                                └─→ Chunk 8 (Tracking)
                                                        └─→ Chunk 9 (Notifications)

Chunk 9 (all backend done)
    ├─→ Chunk 10 (Customer Browse)
    │       └─→ Chunk 11 (Checkout + AI)
    │               └─→ Chunk 12 (Tracking UI)
    ├─→ Chunk 13 (Vendor Dashboard)
    └─→ Chunk 14 (Agent PWA)

All chunks → Chunk 15 (CI/CD)
```

---

## ENV QUICK REFERENCE

| Variable | Used In | Notes |
|---|---|---|
| `DATABASE_URL` | API | PostgreSQL connection string |
| `REDIS_URL` | API | Redis connection |
| `MONGODB_URL` | API | MongoDB for tracking |
| `JWT_SECRET` | API | Min 64 chars random string |
| `JWT_REFRESH_SECRET` | API | Different from JWT_SECRET |
| `RAZORPAY_KEY_ID` | API + Web | rz_test_xxx for dev |
| `RAZORPAY_KEY_SECRET` | API | Server-side only |
| `RAZORPAY_WEBHOOK_SECRET` | API | Set in Razorpay dashboard |
| `OPENAI_API_KEY` | API | For DALL-E 3 cake previews |
| `PLATFORM_FEE_PERCENT` | API | Default: 10 |
| `VITE_API_URL` | Web/Vendor/Agent | http://localhost:4000 in dev |

---

*BakeRoute Chunk Prompts v1.0 — 15 chunks, ~3–5 days of focused building*

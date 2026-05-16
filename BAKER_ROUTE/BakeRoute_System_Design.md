# BakeRoute — Production-Grade System Design Document
> Hyperlocal Bakery Delivery Marketplace | v1.0 | Designed with DDIA Framework

---

## EXECUTIVE SUMMARY

BakeRoute is a hyperlocal, vertically specialized delivery marketplace that faces two structural challenges that Zomato/Uber Eats do NOT face at their core: (1) **high-customization orders** (cake design previews, personalization flows, delivery time windows) that require longer order lead times, and (2) **fragile cargo logistics** — cakes cannot be thrown into standard delivery bags. The architecture must accommodate both a marketplace model (discovery + search) and a specialized logistics network (trained agents, route optimization for fragile goods).

**Core architectural decision**: Event-driven microservices with Kafka as the central nervous system. Every service communicates asynchronously through the event log. The event log IS the source of truth for order state transitions. No direct service-to-service calls for state mutations (eliminates dual-write bugs and reduces coupling).

---

## PHASE 1: REQUIREMENTS ENGINEERING

### 1.1 Functional Requirements

**Customer App/Web (Next.js)**
- Browse and search local bakeries by location, rating, specialty
- View bakery menus with customizable products
- AI-powered cake preview (upload theme/photo → generate mockup)
- Add to cart with customization options (text, flavors, tiers, design)
- Schedule delivery (time slots, minimum lead time enforcement)
- Real-time order tracking (delivery agent GPS)
- Payment via Razorpay (UPI, cards, wallets)
- Order history, re-order, ratings

**Bakery Vendor Dashboard**
- Receive and manage orders in real-time
- Update menu items, pricing, availability
- Set production capacity (max orders per day/slot)
- Mark orders as prepared / ready for pickup
- View revenue analytics and payouts
- Upload cake photos and set customization templates

**Delivery Agent System**
- Receive and accept delivery assignments
- Navigate route via Google Maps integration
- Update delivery status at each milestone
- Fragile cargo checklist enforcement at pickup
- Earnings dashboard

**Platform / Core**
- Order lifecycle management (placed → confirmed → preparing → ready → picked → delivered)
- Payment processing and split settlement (platform fee, bakery payout, agent payout)
- Notification system (push, SMS, email) for all actors
- Search and recommendation engine
- Admin panel for operations

### 1.2 Non-Functional Requirements (Quantified)

| Parameter | Target | Justification |
|-----------|--------|---------------|
| **DAU (launch)** | 10K–50K | City-level hyperlocal; not national Day 1 |
| **DAU (growth target)** | 500K+ | After multi-city expansion |
| **Read QPS (avg)** | 2,000 | Menu browsing, search heavy |
| **Read QPS (peak)** | 15,000 | Festival seasons (Diwali, Valentine's Day) |
| **Write QPS (avg)** | 200 | Order placement, status updates |
| **Write QPS (peak)** | 1,500 | Same festival peaks |
| **Read:Write Ratio** | ~10:1 | Browse-heavy marketplace |
| **Latency SLA (search/browse)** | p50<100ms, p99<400ms | User experience |
| **Latency SLA (order placement)** | p50<300ms, p99<1s | Payment-critical path |
| **Availability** | 99.9% (8.7h downtime/year) | Startup V1; 99.99% is overengineering at launch |
| **Tracking update latency** | <5s | Real-time feels; WebSocket push |
| **Data Retention** | 5 years | Legal + analytics |
| **Geographic scope** | Single city launch | Partition strategy must support multi-city |
| **Consistency** | Strong for payments; Eventual for search/feeds | Per-operation |

### 1.3 Back-of-the-Envelope Estimation

**Storage**
- Orders: 500K DAU × 0.1 orders/user/day × 2KB/order = 100MB/day → ~36GB/year
- GPS tracking events: 1,000 concurrent deliveries × 1 event/5s × 200 bytes = ~3.5GB/day → ~1.3TB/year
- User data: 2M users × 1KB = 2GB
- Menu/catalog: 10K bakeries × 50KB menus = 500MB (mostly static, CDN-able)
- AI-generated cake images: 100K/month × 200KB = 20GB/month → ~240GB/year
- **Total Year 1 estimate: ~2TB raw data** (S3 + databases)

**Compute (Peak)**
- 15K read QPS: 1 Node.js server handles ~2K req/s → need ~8 API servers at peak
- Kafka tracking stream: 1K agents × 12 events/min = 12K events/min (trivial)
- Search: Elasticsearch cluster handles this at 3 nodes

**Network**
- Peak bandwidth: 15K QPS × 5KB avg payload = 75MB/s egress = ~0.6Gbps (manageable)

---

## PHASE 2: DATA MODELS

### 2.1 System of Record vs. Derived Data

```
SYSTEM OF RECORD (PostgreSQL)       DERIVED DATA SYSTEMS
─────────────────────────────       ────────────────────────────────────
users                           →   Redis session cache
orders (canonical state machine)→   Kafka order-events topic → consumer UIs
bakeries                        →   Elasticsearch search index
products                        →   Redis menu cache (per-bakery, 5min TTL)
payments (ledger)               →   Analytics warehouse (ClickHouse)
delivery_assignments            →   MongoDB tracking_events (time-series)
agent_locations (latest only)   →   Redis agent_location cache (30s TTL)
```

**Critical rule applied**: NO service reads another service's database directly. All cross-service data access goes through the event log or dedicated APIs. This is non-negotiable for maintainability.

### 2.2 PostgreSQL Schema (System of Record)

```sql
-- USERS
CREATE TABLE users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone         VARCHAR(15) UNIQUE NOT NULL,
  email         VARCHAR(255),
  name          VARCHAR(100),
  role          VARCHAR(20) NOT NULL CHECK (role IN ('customer','bakery_owner','agent','admin')),
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- BAKERIES
CREATE TABLE bakeries (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id        UUID REFERENCES users(id),
  name            VARCHAR(200) NOT NULL,
  slug            VARCHAR(200) UNIQUE NOT NULL,
  description     TEXT,
  location        GEOGRAPHY(POINT,4326),  -- PostGIS for geospatial queries
  address         JSONB,
  city            VARCHAR(100) NOT NULL,
  rating          NUMERIC(3,2) DEFAULT 0.0,
  rating_count    INTEGER DEFAULT 0,
  is_active       BOOLEAN DEFAULT true,
  operating_hours JSONB,                  -- {"mon":{"open":"08:00","close":"20:00"}}
  max_daily_orders INTEGER DEFAULT 50,
  advance_hours   INTEGER DEFAULT 24,    -- minimum lead time for orders
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- PRODUCTS
CREATE TABLE products (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bakery_id       UUID REFERENCES bakeries(id) ON DELETE CASCADE,
  name            VARCHAR(200) NOT NULL,
  description     TEXT,
  base_price      NUMERIC(10,2) NOT NULL,
  category        VARCHAR(50) NOT NULL,   -- 'cake','pastry','bread','cookie','custom'
  is_customizable BOOLEAN DEFAULT false,
  customization_schema JSONB,            -- {flavors:[...], tiers:[...], message: true}
  images          TEXT[],
  is_available    BOOLEAN DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ORDERS (the critical entity — strong consistency required)
CREATE TABLE orders (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  idempotency_key   UUID UNIQUE NOT NULL,  -- client-generated, deduplication
  customer_id       UUID REFERENCES users(id),
  bakery_id         UUID REFERENCES bakeries(id),
  status            VARCHAR(30) NOT NULL DEFAULT 'pending',
                    -- pending→confirmed→preparing→ready→assigned→picked→delivered|cancelled|refunded
  items             JSONB NOT NULL,         -- snapshot of ordered items at time of order
  customization     JSONB,                  -- cake design details
  delivery_address  JSONB NOT NULL,
  delivery_location GEOGRAPHY(POINT,4326),
  scheduled_at      TIMESTAMPTZ NOT NULL,   -- customer-requested delivery time
  subtotal          NUMERIC(10,2) NOT NULL,
  platform_fee      NUMERIC(10,2) NOT NULL,
  delivery_fee      NUMERIC(10,2) NOT NULL,
  total             NUMERIC(10,2) NOT NULL,
  payment_status    VARCHAR(20) DEFAULT 'pending',
  payment_method    VARCHAR(30),
  razorpay_order_id VARCHAR(100),
  special_notes     TEXT,
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  updated_at        TIMESTAMPTZ DEFAULT NOW()
);
-- Partition by city + created_at for multi-city scale
CREATE INDEX idx_orders_bakery ON orders(bakery_id, status);
CREATE INDEX idx_orders_customer ON orders(customer_id, created_at DESC);
CREATE INDEX idx_orders_scheduled ON orders(scheduled_at, status);

-- PAYMENTS (append-only ledger — NEVER UPDATE, ONLY INSERT)
CREATE TABLE payment_events (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id      UUID REFERENCES orders(id),
  event_type    VARCHAR(30) NOT NULL,  -- 'initiated','captured','failed','refunded','settled'
  amount        NUMERIC(10,2) NOT NULL,
  currency      VARCHAR(5) DEFAULT 'INR',
  gateway_ref   VARCHAR(200),
  metadata      JSONB,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- DELIVERY ASSIGNMENTS
CREATE TABLE delivery_assignments (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id     UUID REFERENCES orders(id) UNIQUE,
  agent_id     UUID REFERENCES users(id),
  status       VARCHAR(20) DEFAULT 'assigned',
               -- assigned→en_route_bakery→at_bakery→en_route_customer→delivered
  pickup_code  VARCHAR(10) NOT NULL,   -- 4-digit PIN for bakery handoff
  assigned_at  TIMESTAMPTZ DEFAULT NOW(),
  picked_at    TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  distance_km  NUMERIC(8,2),
  agent_fee    NUMERIC(10,2)
);

-- RATINGS
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
```

### 2.3 MongoDB Collections (Operational / Tracking)

```javascript
// tracking_events — time-series, high write volume
// Partitioned by agent_id + date
{
  _id: ObjectId,
  agent_id: UUID,
  order_id: UUID,
  location: { type: "Point", coordinates: [lng, lat] },
  status: "en_route_customer",
  speed_kmh: 22,
  bearing: 127,
  timestamp: ISODate("2024-01-15T14:23:00Z"),
  battery_level: 78
}
// Index: { agent_id: 1, timestamp: -1 }, { order_id: 1, timestamp: -1 }
// TTL index: expires after 90 days (raw tracking data)

// bakery_analytics — pre-aggregated for dashboard
{
  bakery_id: UUID,
  date: "2024-01-15",
  orders_received: 45,
  orders_completed: 43,
  orders_cancelled: 2,
  revenue: 87500,
  avg_prep_time_min: 34,
  popular_items: [{ product_id: UUID, count: 12 }]
}
```

### 2.4 Redis Key Design

```
# Session
session:{user_id}                    TTL: 24h    → JWT payload

# Menu cache (cache-aside, invalidated via Kafka CDC)
menu:{bakery_id}                     TTL: 5min   → JSON menu blob

# Agent location (hot real-time data)
agent:loc:{agent_id}                 TTL: 60s    → {lat, lng, updated_at}

# Order tracking subscription (which customers are watching)
tracking:subs:{order_id}             TTL: 4h     → Set of WebSocket connection IDs

# Rate limiting
rl:order:{customer_id}              TTL: 1min   → counter (max 5 orders/min)
rl:api:{ip}                         TTL: 1min   → counter

# Distributed lock (prevent duplicate order placement)
lock:order:{idempotency_key}        TTL: 30s    → 1
```

---

## PHASE 3: MICROSERVICES ARCHITECTURE

### Service Breakdown

| Service | Responsibility | Database | Language |
|---------|---------------|----------|---------|
| **API Gateway** | Rate limiting, auth, routing | Redis (sessions) | Node.js |
| **Auth Service** | OTP login, JWT issue/refresh | PostgreSQL | Node.js |
| **Catalog Service** | Bakeries, menus, products CRUD | PostgreSQL + Elasticsearch | Node.js |
| **Order Service** | Order state machine, placement | PostgreSQL (SERIALIZABLE isolation) | Node.js |
| **Payment Service** | Razorpay integration, ledger | PostgreSQL (append-only) | Node.js |
| **Delivery Service** | Agent assignment, routing | PostgreSQL + Redis | Node.js |
| **Tracking Service** | GPS ingestion, WebSocket push | MongoDB + Redis | Node.js |
| **Notification Service** | Push/SMS/email dispatch | Queue consumer | Node.js |
| **Search Service** | Full-text + geo search | Elasticsearch | Node.js |
| **Recommendation Service** | Personalized suggestions | Redis + ClickHouse | Python (ML) |
| **AI Preview Service** | Cake design generation | External API (Stability AI / DALL-E) | Python |
| **Analytics Service** | Reporting, dashboards | ClickHouse | Node.js |
| **Admin Service** | Ops dashboard, interventions | PostgreSQL | Node.js |

### Critical: Order State Machine (Order Service)

```
PENDING ──[payment_captured]──→ CONFIRMED
CONFIRMED ──[bakery_accepts]──→ PREPARING
PREPARING ──[bakery_marks_ready]──→ READY
READY ──[agent_assigned]──→ ASSIGNED
ASSIGNED ──[agent_picks_up]──→ PICKED
PICKED ──[agent_delivers]──→ DELIVERED ✓

Any state → CANCELLED (with compensation logic)
DELIVERED → REFUND_REQUESTED → REFUNDED (if disputed)
```

**Implementation**: Every state transition is:
1. Validated against allowed transitions (reject invalid)
2. Wrapped in PostgreSQL SSI transaction
3. Written to `orders` table
4. CDC via Debezium → Kafka `order-events` topic
5. Downstream services (Notification, Delivery, Analytics) consume and react

This is the Saga pattern. No 2PC. Each service handles its own compensation.

---

## PHASE 4: KAFKA EVENT ARCHITECTURE

### Topics

```
order-events            # All order state transitions (partitioned by order_id)
payment-events          # Payment gateway webhooks + internal events
tracking-events         # Agent GPS pings (partitioned by agent_id, high volume)
notification-events     # Trigger notifications for any actor
catalog-events          # Menu/product updates for cache invalidation
analytics-events        # User behavior for recommendation engine
ai-preview-jobs         # Async cake preview generation requests
```

### Event Flow Example: Order Placement

```
Customer → [POST /orders] → API Gateway → Order Service
Order Service:
  1. Acquire Redis distributed lock (idempotency_key)
  2. Validate cart, check bakery capacity
  3. CREATE Razorpay order
  4. INSERT order (status=pending) in PostgreSQL
  5. Publish to Kafka: order-events { order_id, status: 'pending', ... }
  6. Return Razorpay payment_link to customer

Payment Gateway → webhook → Payment Service:
  1. Verify Razorpay signature
  2. INSERT payment_event (captured)
  3. Publish: payment-events { order_id, status: 'captured' }

Order Service (consuming payment-events):
  1. UPDATE order status → confirmed
  2. Publish: order-events { order_id, status: 'confirmed' }

Notification Service (consuming order-events):
  → Push to customer: "Order confirmed!"
  → Push to bakery dashboard: "New order #XYZ"

Delivery Service (consuming order-events where status='ready'):
  → Find nearest available trained agent
  → INSERT delivery_assignment
  → Publish: order-events { order_id, status: 'assigned', agent_id }
```

---

## PHASE 5: REAL-TIME TRACKING SYSTEM

### Architecture

```
Agent Mobile App
    │ (HTTPS POST every 5s when active)
    ↓
Tracking Service (Node.js, stateless, 3+ pods)
    │
    ├── Write to MongoDB tracking_events (async, fire-and-forget)
    ├── SETEX Redis: agent:loc:{agent_id} = {lat, lng} TTL=60s
    ├── Publish to Kafka: tracking-events
    └── Publish to Redis Pub/Sub: channel tracking:{order_id}

WebSocket Server (separate pod, sticky sessions via NGINX ip_hash)
    │ (Subscribed to Redis Pub/Sub: tracking:{order_id})
    ↓ (Push to connected customer client every update)
Customer Browser/App
```

**Why two systems (Kafka + Redis Pub/Sub)?**
- Kafka: durable, for analytics, route reconstruction, SLA monitoring
- Redis Pub/Sub: ephemeral, ultra-low latency for live customer UI push

**WebSocket connection management**:
- Customer opens order tracking → WebSocket handshake via `/ws/track/{order_id}`
- Server joins Redis Pub/Sub channel `tracking:{order_id}`
- On disconnect → unsubscribe (cleanup)
- Horizontal scaling: NGINX with `ip_hash` for sticky sessions OR use Redis to store which node holds which connection

### Agent Location API

```javascript
// POST /api/tracking/location
// Headers: Authorization: Bearer {agent_jwt}
{
  "order_id": "uuid",
  "lat": 23.0225,
  "lng": 72.5714,
  "speed_kmh": 18,
  "bearing": 215,
  "battery": 82
}
// Response: 200 OK { next_checkpoint: {...} }
```

---

## PHASE 6: SEARCH & RECOMMENDATION SYSTEM

### Search Architecture

**Elasticsearch** (3-node cluster) for:
- Full-text search on bakery name, description, product names
- Geospatial queries (bakeries within X km of user)
- Faceted filtering (rating ≥ 4, min price, specialty)
- Autocomplete (prefix queries on bakery/product names)

**Data pipeline**: PostgreSQL → Debezium CDC → Kafka `catalog-events` → Elasticsearch Consumer Service → Update ES index

**Why not search directly in PostgreSQL?**
Because text search in PostgreSQL is limited, has no geospatial + text composite ranking, and adding heavy read traffic to the OLTP source is a textbook anti-pattern.

```javascript
// Search API: GET /api/search/bakeries?q=chocolate+cake&lat=23.02&lng=72.57&radius_km=5
{
  "query": {
    "bool": {
      "must": [{ "multi_match": { "query": "chocolate cake", "fields": ["name^2","description","products.name"] }}],
      "filter": [
        { "geo_distance": { "distance": "5km", "location": { "lat": 23.02, "lon": 72.57 }}},
        { "term": { "is_active": true }}
      ]
    }
  },
  "sort": [
    { "_score": "desc" },
    { "rating": "desc" }
  ]
}
```

### Recommendation Engine

**V1 (Launch)**: Rule-based. No ML required yet.
- "Popular near you" → Redis sorted set: `popular:{city}:{category}` scored by order count (updated hourly via batch)
- "You might like" → Collaborative filtering is overkill at <50K DAU. Use: ordered before in same category → recommend similar products

**V2 (Post-PMF)**: Item-to-item collaborative filtering using ClickHouse analytics. Python service exposes recommendations via REST API cached in Redis.

---

## PHASE 7: API DESIGN

### Authentication
All APIs require `Authorization: Bearer {jwt}` except public browse/search endpoints.
JWT payload: `{ user_id, role, city, exp }`

### Key Endpoints

```
POST /api/auth/send-otp          { phone } → { request_id }
POST /api/auth/verify-otp        { request_id, otp } → { access_token, refresh_token }

GET  /api/bakeries               ?lat&lng&radius&q&page → [bakery list]
GET  /api/bakeries/:id/menu      → { bakery, products }
GET  /api/bakeries/:id/slots     ?date → [available time slots]

POST /api/orders                 { bakery_id, items, customization, delivery_address, scheduled_at, idempotency_key }
GET  /api/orders/:id             → { order + current status }
GET  /api/orders                 ?page → [customer's orders]

GET  /api/tracking/:order_id     → { agent location, ETA, status }
WS   /ws/track/:order_id         → stream { lat, lng, status, eta }

POST /api/payments/webhook       (Razorpay → internal, signature-verified)

POST /api/ai/cake-preview        { theme, text, style, base64_reference_image } → { preview_url }

GET  /api/vendor/orders          → [bakery's pending/active orders]
PUT  /api/vendor/orders/:id/status { status: 'preparing'|'ready' }

GET  /api/agent/assignment       → { current order assignment }
PUT  /api/agent/status           { status: 'available'|'busy'|'offline' }
```

### Rate Limiting Strategy

| Endpoint | Limit | Window |
|----------|-------|--------|
| OTP send | 3 requests | 15 min per phone |
| Order placement | 5 | 1 min per user |
| Search/browse | 100 | 1 min per IP |
| AI preview | 10 | 1 hour per user |
| Agent location update | 30 | 1 min per agent |

---

## PHASE 8: PAYMENT ARCHITECTURE

### Razorpay Integration Flow

```
1. Customer confirms order → POST /api/orders
2. Order Service creates Razorpay Order (server-side, captures order amount)
3. Client receives { razorpay_order_id, amount } and opens Razorpay checkout
4. Customer pays → Razorpay calls webhook: POST /api/payments/webhook
5. Payment Service:
   a. Verify webhook signature (HMAC-SHA256)
   b. INSERT payment_event {captured}
   c. Publish payment-events to Kafka
6. Order Service consumes → updates order status = confirmed
```

### Settlement Architecture

```
Payment captured: ₹500
  Platform fee: ₹50 (10%)
  Delivery fee: ₹40
  Bakery amount: ₹410

Payout schedule:
  Bakery: T+2 days via Razorpay Route
  Agent: Weekly via NEFT/UPI
  Platform: Razorpay Route auto-splits at capture
```

**Critical**: Payment events table is append-only (no UPDATEs). State is derived from the event sequence. Idempotency keys on all Razorpay calls to handle retries safely.

---

## PHASE 9: AI CAKE PREVIEW SERVICE

### Architecture

```
Customer uploads → S3 (pre-signed URL upload)
POST /api/ai/cake-preview { s3_key, theme, text, style }
    ↓
AI Preview Service publishes job → Kafka: ai-preview-jobs
    ↓
AI Worker Pod (Python, GPU-enabled if using local model, else API call)
    → Calls Stability AI / DALL-E API with structured prompt
    → Stores result in S3
    → Publishes completion event → Kafka
    ↓
Notification Service pushes preview_url to customer WebSocket
```

**Prompt engineering template**:
```
"Professional bakery cake photograph, {theme} theme, {flavor} flavored, 
{tiers} tier cake with the text '{custom_text}' written in {style} frosting. 
Studio lighting, white background, hyper-realistic food photography."
```

**V1 approach**: Use external API (OpenAI DALL-E 3 or Stability AI). Async via Kafka job queue.
**V2**: Fine-tune a LoRA model on Indian cake styles if external API costs become significant.

---

## PHASE 10: CLOUD INFRASTRUCTURE (AWS)

### Architecture Diagram (Textual)

```
Internet → AWS CloudFront (CDN) → Application Load Balancer
                                         │
                           ┌─────────────┼─────────────┐
                      NGINX (API GW)  WebSocket Pods  Next.js SSR
                           │
              ┌────────────┼────────────────────────────┐
         Auth Service  Order Service  Tracking Service  ...other microservices
              │               │              │
    ┌─────────┼───────┐    Kafka          MongoDB
   PG Primary  PG     Redis Cluster     (tracking)
              Read
             Replicas
              │
           ClickHouse
           (Analytics)
              │
          Elasticsearch
           (Search)
```

### AWS Services Used

| Component | AWS Service | Justification |
|-----------|------------|---------------|
| Container orchestration | EKS (Kubernetes) | Auto-scaling, managed control plane |
| PostgreSQL | RDS PostgreSQL 15 + Read Replicas | Managed, Multi-AZ, automated backups |
| Redis | ElastiCache Redis 7 (cluster mode) | Sub-ms latency, managed |
| Message Queue | MSK (Managed Kafka) | Managed Kafka, removes operational burden |
| Search | Amazon OpenSearch or self-hosted ES on EC2 | Cost tradeoff |
| Object Storage | S3 | Images, AI previews, logs |
| CDN | CloudFront | Static assets, menu images |
| Secrets | AWS Secrets Manager | DB creds, API keys |
| DNS | Route 53 | Geo-routing for multi-city |
| Email | SES | Transactional emails |
| SMS | SNS or Exotel (India) | OTP, delivery notifications |
| Push Notifications | FCM via SNS | Mobile push |
| Monitoring | CloudWatch + Datadog | Metrics, logs, alerts |
| Load Balancer | ALB | HTTP/WebSocket, path-based routing |

### Region Strategy
- **Launch**: ap-south-1 (Mumbai) — lowest latency for India
- **Multi-region later**: Replicate read replicas to other regions

---

## PHASE 11: KUBERNETES DEPLOYMENT

### Cluster Layout

```yaml
# Namespaces
bakeroute-prod        # All production services
bakeroute-monitoring  # Prometheus, Grafana, Jaeger
bakeroute-infra       # Kafka, Redis (or managed services)
```

### Sample Deployment: Order Service

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  namespace: bakeroute-prod
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0           # Zero downtime deployments
  selector:
    matchLabels:
      app: order-service
  template:
    spec:
      containers:
      - name: order-service
        image: bakeroute/order-service:v1.2.3
        ports:
        - containerPort: 3000
        env:
        - name: DB_URL
          valueFrom:
            secretKeyRef:
              name: db-secrets
              key: postgres-url
        - name: KAFKA_BROKERS
          value: "kafka-0.kafka:9092,kafka-1.kafka:9092"
        resources:
          requests:
            cpu: "250m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        readinessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 20
          periodSeconds: 10
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: order-service-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: order-service
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
```

### Ingress (NGINX)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    # WebSocket upgrade support
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "Upgrade";
spec:
  rules:
  - host: api.bakeroute.in
    http:
      paths:
      - path: /ws/
        pathType: Prefix
        backend:
          service:
            name: tracking-service
            port:
              number: 3001
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-gateway
            port:
              number: 3000
```

---

## PHASE 12: DEVOPS PIPELINE (CI/CD)

```
GitHub PR → GitHub Actions
    │
    ├── Lint (ESLint, Prettier)
    ├── Unit Tests (Jest)
    ├── Integration Tests (Testcontainers — spins real PostgreSQL + Redis)
    ├── Build Docker Image
    ├── Vulnerability Scan (Trivy)
    └── Push to ECR (AWS Container Registry)

Merge to main → ArgoCD (GitOps)
    │
    ├── Staging cluster: auto-deploy
    ├── E2E Tests (Playwright)
    └── Production: manual approval gate → rolling deploy

Monitoring:
    ├── Datadog APM (distributed tracing)
    ├── Prometheus + Grafana (cluster metrics)
    ├── PagerDuty (on-call alerts)
    └── Sentry (error tracking)
```

### Key GitHub Actions Workflow

```yaml
name: CI
on: [pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: test
      redis:
        image: redis:7
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: npm ci
      - run: npm run lint
      - run: npm test -- --coverage
      - run: npm run test:integration
      
  build:
    needs: test
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
      - run: docker build -t bakeroute/$SERVICE:${{ github.sha }} .
      - run: trivy image bakeroute/$SERVICE:${{ github.sha }}
      - run: docker push $ECR_REGISTRY/bakeroute/$SERVICE:${{ github.sha }}
```

---

## PHASE 13: SECURITY

### Authentication & Authorization
- OTP via phone (no password — reduces breach surface)
- JWT: short-lived access tokens (15min) + long-lived refresh tokens (30 days)
- Refresh token rotation (each use issues new one, invalidates old)
- Role-based access: customer/bakery_owner/agent/admin enforced at API Gateway level

### Data Security
- All PII encrypted at rest (RDS encryption + S3 SSE-KMS)
- All traffic TLS 1.3 minimum
- Payment data: PCI-DSS compliance via Razorpay (platform never stores card data)
- Razorpay webhook signature verification (HMAC-SHA256)
- Agent location data: only visible to the customer whose order is being delivered

### API Security
- Rate limiting at API Gateway (Redis token bucket)
- CORS: whitelist frontend domains only
- Input validation (Zod schemas on all endpoints)
- SQL injection: parameterized queries only (no raw SQL string concat)
- Secrets: AWS Secrets Manager, no secrets in code or environment files in repo

### Network Security
- VPC with private subnets for all databases and services
- Security groups: minimal surface (DB only accessible from app subnet)
- WAF (AWS WAF) in front of CloudFront for DDoS, SQLi, XSS protection

---

## PHASE 14: CACHING STRATEGY

| Data | Cache Layer | TTL | Invalidation |
|------|-------------|-----|--------------|
| Bakery menu | Redis (cache-aside) | 5 min | Kafka catalog-event → consumer deletes key |
| Search results | CDN (CloudFront) | 30s | Short TTL preferred over cache invalidation complexity |
| User session | Redis | 24h | Logout → explicit delete |
| Agent location | Redis (SETEX) | 60s | Overwritten every 5s by GPS ping |
| Popular bakeries | Redis sorted set | 1h | Batch job rewrites hourly |
| Static assets (images, JS, CSS) | CloudFront | 1 year + content hash | Deploy new hash = new URL |

**Cache-aside pattern** (NOT write-through) for menus:
- Read: check Redis → miss → read PostgreSQL → write Redis → return
- Write: write PostgreSQL → publish Kafka event → consumer deletes Redis key
- Why not write-through: bakery menu updates are infrequent, cache miss cost is low, write-through adds coupling

---

## PHASE 15: SCALABILITY STRATEGY

### Horizontal Scaling (Phase 1 → Phase 2)

| Load | Strategy |
|------|----------|
| API traffic ×10 | HPA auto-scales pods; stateless services scale linearly |
| Database reads ×10 | Add PostgreSQL read replicas; route read queries via PgBouncer |
| Search ×10 | Add Elasticsearch data nodes |
| Tracking events ×10 | Add Kafka partitions + tracking service pods |
| Multi-city | Add city column to partition key; deploy city-specific Elasticsearch indices |

### PostgreSQL Partitioning (for orders table)

```sql
-- Range partition by month + hash by city
CREATE TABLE orders_2024_01 PARTITION OF orders
  FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- At multi-city scale, shard by city using Citus extension
-- or migrate to distributed SQL (CockroachDB)
```

### When to Break the Monolith vs. Microservices

**Do NOT start with 15 microservices on Day 1.** That is operational insanity for a 2–5 person startup.

**Recommended evolution**:
- **Month 1–3**: Single Next.js app + single Node.js API + PostgreSQL + Redis
- **Month 4–6**: Extract Tracking Service (different scaling needs — WebSocket + high write volume)
- **Month 7–12**: Extract Payment Service (compliance boundary) + Notification Service
- **Year 2+**: Extract remaining services as team grows

The microservice diagram above is the **target architecture**, not the launch architecture.

---

## PHASE 16: TRADE-OFF ANALYSIS

| Decision | Option A | Option B | Chosen | Rationale |
|----------|----------|----------|--------|-----------|
| Order state | PostgreSQL (strong) | MongoDB (flexible) | **PostgreSQL** | Financial data needs ACID; state machine requires strong consistency |
| Tracking storage | PostgreSQL | MongoDB | **MongoDB** | High write volume, time-series, no joins needed; document model perfect |
| Message broker | Kafka | RabbitMQ | **Kafka** | Kafka's log retention enables replay, CDC, audit; RabbitMQ deletes on consume |
| Search | Elasticsearch | PostgreSQL full-text | **Elasticsearch** | Geo + text composite ranking; don't hammer OLTP with heavy reads |
| Agent routing | In-house algo | Google Maps API | **Google Maps API** | Route optimization is a solved problem; not BakeRoute's core IP |
| WebSockets | Custom WS server | Socket.io | **Custom (ws library)** | Avoids Socket.io polling fallback overhead; agents are mobile (5G) |
| AI cake preview | DALL-E 3 external | Self-hosted Stable Diffusion | **DALL-E 3 (V1)** | Faster to ship; revisit when volume drives cost |
| Multi-tenancy | Shared DB, row-level | Separate DB per bakery | **Shared DB** | Operational nightmare at 10K bakeries; row-level isolation is sufficient |
| Payment | Razorpay | Stripe | **Razorpay** | India-first, UPI support, lower MDR for Indian cards, Razorpay Route for splits |

---

## PHASE 17: CAPACITY PLANNING & COST ESTIMATE (Monthly, India)

| Resource | Spec | Monthly Cost |
|----------|------|-------------|
| EKS cluster | 3x m5.xlarge workers | ~₹45,000 |
| RDS PostgreSQL | db.m5.large Multi-AZ | ~₹18,000 |
| ElastiCache Redis | cache.m5.large | ~₹8,000 |
| MSK Kafka | 2 broker.m5.large | ~₹22,000 |
| MongoDB Atlas | M10 cluster | ~₹6,000 |
| Elasticsearch | 3x r5.large | ~₹30,000 |
| CloudFront | 10TB/month | ~₹6,000 |
| S3 | 2TB storage | ~₹2,000 |
| SES + SNS | 1M emails + SMS | ~₹8,000 |
| AI Preview API | 50K calls/month | ~₹40,000 |
| **Total** | | **~₹1,85,000/month (~$2,200)** |

**Cost optimization levers**:
- Use Spot instances for Kafka brokers (not stateful in managed MSK)
- Use Reserved Instances for RDS (1-year saves ~40%)
- Cache aggressively to reduce DB compute
- Compress tracking events before Kafka (JSON → Protocol Buffers)
- Use S3 Intelligent-Tiering for old images

---

## PHASE 18: OBSERVABILITY

### The Three Pillars

**Metrics (Prometheus + Grafana)**
- API latency (p50, p95, p99) per endpoint
- Order placement success rate
- Payment capture rate vs. failure rate
- Kafka consumer lag (alert if lag > 10K messages)
- Active WebSocket connections
- Agent GPS update frequency

**Logging (CloudWatch + structured JSON)**
```json
{
  "timestamp": "2024-01-15T14:23:00Z",
  "service": "order-service",
  "level": "INFO",
  "trace_id": "abc123",
  "user_id": "uuid",
  "order_id": "uuid",
  "event": "order_status_changed",
  "from": "confirmed",
  "to": "preparing",
  "duration_ms": 45
}
```

**Tracing (Jaeger / AWS X-Ray)**
- Distributed trace: API Gateway → Order Service → PostgreSQL → Kafka
- Critical for debugging latency in multi-service flows

### Alerting Rules

| Alert | Threshold | Action |
|-------|-----------|--------|
| Payment failure rate | >5% in 5min | Page on-call |
| Order service error rate | >1% in 2min | Page on-call |
| DB connection pool exhaustion | >80% | Auto-scale + page |
| Kafka consumer lag | >50K messages | Page on-call |
| Agent GPS last seen | >2min for active delivery | Trigger manual check |
| P99 latency (search) | >2s | Warning |

---

## KNOWN LIMITATIONS & EVOLUTION STRATEGY

### Current Limitations
1. **Single region** — any AWS Mumbai outage = full downtime
2. **No real-time inventory** — race condition if bakery runs out mid-order during peak
3. **AI preview latency** — external API call adds 5–15s delay; async mitigates UX impact
4. **Agent matching** — simple nearest-agent algorithm; no multi-stop route optimization at V1

### 10x Growth Strategy
1. Add PostgreSQL read replicas + PgBouncer connection pooling
2. Partition orders table by city + month
3. Multi-region deployment (Mumbai primary + Pune/Bangalore replicas)
4. Migrate to Citus (distributed PostgreSQL) or CockroachDB if single-node hits limits
5. Implement proper inventory reservation (Saga with compensating transactions)
6. Build proprietary route optimization for fragile delivery (differentiator vs. standard delivery)

---

*Document Version: 1.0 | Architecture Review Recommended at: 100K DAU milestone*

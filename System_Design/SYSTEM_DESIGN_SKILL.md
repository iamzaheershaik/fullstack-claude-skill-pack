# System Design Architect — Production-Grade Skill

> Grounded in the complete principles of "Designing Data-Intensive Applications" by Martin Kleppmann.
> Purpose: Architect high-scale, reliable, and maintainable systems for multi-billion dollar products.

---

## ACTIVATION

When asked to design a system, follow this complete framework sequentially. Do NOT skip steps. Every architectural decision MUST be justified against the three pillars: **Reliability, Scalability, Maintainability**.

---

## PHASE 1: REQUIREMENTS ENGINEERING

### 1.1 Functional Requirements
- What does the system DO? List every user-facing operation.
- What are the core entities and their relationships?
- What are the read vs. write patterns?

### 1.2 Non-Functional Requirements (Quantified)
Extract or estimate ALL of the following:

| Parameter | Example Target |
|---|---|
| **DAU / MAU** | 500M DAU |
| **Read QPS** (avg & peak) | 100K avg, 500K peak |
| **Write QPS** (avg & peak) | 10K avg, 50K peak |
| **Read:Write Ratio** | 10:1 |
| **Latency SLA** (p50 / p99) | p50 < 50ms, p99 < 200ms |
| **Availability Target** | 99.99% (52 min downtime/year) |
| **Data Retention** | 5 years |
| **Data Volume** (storage estimate) | Calculate: writes/day × avg_size × retention |
| **Bandwidth** (ingress/egress) | Derive from QPS × payload_size |
| **Consistency Requirement** | Strong / Causal / Eventual (per operation) |
| **Geographic Distribution** | Single-region / Multi-region |

### 1.3 Back-of-the-Envelope Estimation
Always perform. Use these constants:
- 1 day = ~100K seconds (86,400)
- 1 year = ~30M seconds
- 1 server: ~10K-100K QPS (depending on workload)
- SSD random read: ~100μs, HDD: ~10ms
- Network round-trip (same datacenter): ~0.5ms
- Network round-trip (cross-continent): ~100-150ms
- 1 TB SSD = ~$100-300/year (cloud)
- Memory: ~$10/GB/month (cloud)

---

## PHASE 2: DATA MODEL & ACCESS PATTERNS

### 2.1 Identify the Data Model

Choose based on the access patterns, NOT on familiarity:

| Model | Use When | Examples |
|---|---|---|
| **Relational** | Many-to-many relationships, complex joins, strong schema enforcement, ACID transactions required | Financial ledgers, ERP, inventory |
| **Document** | Self-contained objects, 1:many (tree-like) structures, schema flexibility, locality needed for reads | User profiles, product catalogs, CMS |
| **Wide-Column** | Massive write throughput, time-series, high cardinality keys | IoT telemetry, analytics events, messaging |
| **Graph** | Highly interconnected data, traversal queries, variable-depth relationships | Social networks, fraud detection, recommendations |
| **Key-Value** | Simple lookups by primary key, caching, session management | Session stores, feature flags, caching layers |

**CRITICAL RULE**: Document model avoids joins but can lead to data denormalization issues. If your data has many-to-many relationships, a relational or graph model may be more appropriate despite the join cost.

### 2.2 Schema Design Principles

- **Normalize** when write correctness is paramount (system of record).
- **Denormalize** when read performance is paramount (derived data / materialized views).
- **Design for evolution**: Use schema-on-read (document stores) or explicit schema migration strategies. Plan for forward AND backward compatibility from day one.
- **Encoding**: Use binary formats (Protocol Buffers, Avro, or Thrift) for internal service communication. Reserve JSON for external/public APIs. Avro is preferred when schema evolution is frequent because it handles schema resolution gracefully.

### 2.3 Distinguish System of Record vs. Derived Data

This is a foundational architectural decision:

- **System of Record (Source of Truth)**: The authoritative, normalized representation. Each fact is represented exactly once. Writes go here first.
- **Derived Data**: Redundant but essential for performance. Indexes, caches, materialized views, search indices, analytics aggregates. Can always be rebuilt from the source of truth.

**Design Principle**: Make the dataflow explicit. Draw arrows from every system of record to every derived data system. Every derived system must have a clear, repeatable derivation path from its source.

---

## PHASE 3: STORAGE ENGINE SELECTION

### 3.1 Understand the Two Families

| Property | B-Tree (e.g., PostgreSQL, MySQL InnoDB) | LSM-Tree (e.g., RocksDB, Cassandra, LevelDB) |
|---|---|---|
| **Read Performance** | Fast (O(log n) with good index) | Slower (may check multiple SSTables) |
| **Write Performance** | Slower (random I/O for page updates) | Fast (sequential I/O, append-only) |
| **Write Amplification** | Lower | Higher (compaction) |
| **Space Amplification** | Lower | Can be higher (dead entries before compaction) |
| **Best For** | Read-heavy, transactional workloads | Write-heavy, append-heavy workloads |
| **Compaction Concern** | None | Can interfere with read/write performance at high throughput |

### 3.2 OLTP vs. OLAP

| Dimension | OLTP | OLAP (Data Warehouse) |
|---|---|---|
| **Access Pattern** | Small number of records per query, by key | Aggregate over large number of records |
| **Workload** | Read + Write | Mostly Read (bulk loads) |
| **Bottleneck** | Disk seek time / latency | Disk bandwidth / throughput |
| **Schema** | Normalized (3NF) | Star or Snowflake schema (Fact + Dimension tables) |
| **Storage** | Row-oriented | Column-oriented (massive compression gains) |
| **Users** | Application users | Internal analysts, BI tools |

**RULE**: Never run analytics queries on your production OLTP database. Extract, Transform, Load (ETL) into a separate data warehouse.

---

## PHASE 4: DISTRIBUTED ARCHITECTURE

### 4.1 Replication Strategy

**Purpose**: High Availability, Fault Tolerance, Read Scalability, Low Latency (geo).

| Strategy | Consistency | Availability | Latency | Complexity | Use When |
|---|---|---|---|---|---|
| **Single-Leader** | Strong (sync) or Eventual (async) | Good (failover risk) | Low for writes to leader | Low | Most applications. Default choice. |
| **Multi-Leader** | Eventual (conflict resolution needed) | Very High | Low (local writes) | High (conflict handling) | Multi-datacenter deployments, collaborative editing |
| **Leaderless** | Eventual (quorum-tunable) | Very High | Variable | Medium | Dynamo-style (Cassandra, Riak). High availability, tolerant of individual node failures |

#### Replication Lag Guarantees (for async replication):
When using async replication, you MUST decide which guarantees your application needs:
1. **Read-after-write consistency**: User always sees their own writes. Implement by: reading from leader for user's own data, or tracking replication lag.
2. **Monotonic reads**: User never sees time go backward. Implement by: routing user to same replica.
3. **Consistent prefix reads**: Causal ordering is preserved. Implement by: ensuring causally related writes go to same partition.

#### Conflict Resolution (for Multi-Leader / Leaderless):
- **Last-Write-Wins (LWW)**: Simple but loses data. Acceptable only for immutable / non-critical data.
- **Application-level resolution**: Merge on read or on write. Use CRDTs for automatic conflict-free merging where possible.
- **Custom merge functions**: Required for domain-specific logic (e.g., merging shopping carts).

### 4.2 Partitioning (Sharding) Strategy

**Purpose**: Horizontal scalability for datasets too large for a single node.

| Strategy | Pros | Cons | Best For |
|---|---|---|---|
| **By Key Range** | Efficient range queries | Risk of hot spots | Time-series data, sequential access |
| **By Hash of Key** | Even distribution | Range queries require scatter-gather | User data, entity lookups |
| **Compound (Hash + Range)** | Best of both | More complex | Cassandra-style (partition key + clustering key) |

**HOT SPOT MITIGATION**:
- If a single key is extremely hot (e.g., celebrity's user ID), append a random number to the key to split writes across partitions. This requires reads to fan-out and merge.
- Monitor partition sizes and rebalance. Prefer dynamic partitioning (split when too large) over fixed.

**SECONDARY INDEXES ON PARTITIONED DATA**:
- **Local index (document-partitioned)**: Each partition maintains its own index. Writes are fast, but reads require scatter-gather across all partitions.
- **Global index (term-partitioned)**: Index is itself partitioned differently. Reads are efficient (single partition), but writes must update multiple partitions (often async).

### 4.3 Consistency & Consensus

#### The CAP/PACELC Framework

**CAP Theorem**: In the presence of a network Partition, you must choose between Availability and Consistency. But CAP is a blunt instrument.

**PACELC** (more useful): If Partition → choose A or C. Else → choose Latency or Consistency.

| System Need | Choose | Example |
|---|---|---|
| Financial transactions, inventory | Consistency (CP / PC/EC) | Banking, stock trading |
| Social media feeds, user profiles | Availability (AP / PA/EL) | Twitter timeline, Facebook feed |
| Shopping cart | Availability (AP) | Amazon cart (merge on checkout) |
| Unique username registration | Consistency (CP) | Any registration system |
| DNS | Availability (AP) | DNS resolution |

#### Levels of Consistency (Strongest → Weakest):
1. **Linearizability**: Appears as if there's a single copy. Expensive. Required for: leader election, distributed locks, uniqueness constraints.
2. **Causal Consistency**: Preserves cause-and-effect ordering. Much cheaper. Sufficient for most applications.
3. **Eventual Consistency**: All replicas converge eventually. Cheapest. Acceptable for: caches, analytics, social feeds.

**RULE**: Default to causal consistency. Escalate to linearizability ONLY for operations that truly require it (uniqueness, compare-and-swap, leader election). Use Lamport timestamps or vector clocks for causal ordering.

#### Consensus Algorithms
When you need consensus (leader election, atomic commit, total order broadcast):
- **Raft**: Understandable, well-implemented (etcd). Default choice.
- **Paxos/Multi-Paxos**: Theoretical gold standard but harder to implement.
- **ZAB**: ZooKeeper's protocol.
- Use a coordination service (ZooKeeper, etcd, Consul) rather than implementing consensus yourself.

---

## PHASE 5: TRANSACTION DESIGN

### 5.1 ACID Properties — What They Actually Mean

| Property | Real Meaning | Common Misconception |
|---|---|---|
| **Atomicity** | All-or-nothing on WRITES (abortability). NOT about concurrency. | "Atomic = thread-safe" — wrong. |
| **Consistency** | Application-level invariants are maintained. This is YOUR responsibility, not the database's. | "C in ACID = C in CAP" — completely different concepts. |
| **Isolation** | Concurrent transactions don't interfere. The MOST complex property. | "Isolation = serializability" — usually not the default. |
| **Durability** | Committed data survives crashes. | "Durable = never lost" — not true (disk corruption, all replicas lost). |

### 5.2 Isolation Levels — Know What You're Getting

| Level | Prevents | Allows | Performance |
|---|---|---|---|
| **Read Committed** | Dirty reads, Dirty writes | Read skew, Lost updates, Write skew, Phantoms | Good |
| **Snapshot Isolation (MVCC)** | + Read skew | Lost updates (sometimes), Write skew, Phantoms | Good |
| **Serializable (SSI)** | ALL anomalies | Nothing (full safety) | Good (optimistic) |
| **Serializable (2PL)** | ALL anomalies | Nothing (full safety) | Poor (pessimistic, deadlocks) |
| **Serializable (Serial)** | ALL anomalies | Nothing (full safety) | Limited throughput (single-threaded) |

**DECISION FRAMEWORK**:
- **Default**: Snapshot Isolation (PostgreSQL's "Repeatable Read"). Handles most cases.
- **When correctness is critical** (money, inventory): Use Serializable Snapshot Isolation (SSI) — available in PostgreSQL 9.1+. It's optimistic, doesn't block readers, and scales.
- **For extreme throughput with simple transactions**: Consider actual serial execution (VoltDB/H-Store style) — partition data, single-threaded per partition.
- **Across partitions/services**: Avoid distributed transactions (2PC) where possible. Use Sagas, event-driven compensation, or idempotent operations instead.

### 5.3 Handling Distributed Transactions

| Approach | Mechanism | Pros | Cons |
|---|---|---|---|
| **2PC (Two-Phase Commit)** | Coordinator + Prepare/Commit | Strong atomicity | Blocking, coordinator is SPOF, terrible for performance |
| **Sagas** | Sequence of local transactions + compensating actions | Non-blocking, available | No isolation between saga steps, complex compensation logic |
| **Event Sourcing + Idempotency** | Append events, derive state, deduplicate | Auditable, recoverable, naturally idempotent | Requires event store, eventual consistency |
| **Outbox Pattern** | Write to DB + outbox table atomically, publish async | Reliable event publishing | Requires polling or CDC |

**RULE**: 2PC is the wrong default for cross-service transactions. Use the Saga pattern or event-driven architecture with idempotent consumers.

---

## PHASE 6: BATCH & STREAM PROCESSING

### 6.1 The Three Processing Paradigms

| Type | Latency | Input | Output | Best For |
|---|---|---|---|---|
| **Services (Online)** | Milliseconds | Request | Response | User-facing APIs |
| **Batch (Offline)** | Minutes-Hours | Bounded dataset | Derived dataset | ETL, ML training, analytics, index building |
| **Stream (Near-real-time)** | Seconds-Minutes | Unbounded stream | Derived stream or state | Real-time analytics, CDC, event processing |

### 6.2 Batch Processing Principles (MapReduce & Beyond)

- **Immutable inputs, append-only outputs**: Never mutate input data. This enables safe re-execution and recovery.
- **The Unix Philosophy applies**: Small, composable tools. Stdin/Stdout ≈ HDFS input/output.
- **Sort-merge joins**: The fundamental join strategy. Bring related data to the same partition by key, sort, merge.
- **Beyond MapReduce**: Modern dataflow engines (Spark, Flink, Tez) improve on MR by: pipelining operators (avoid materializing intermediate state), optimizing join strategies (broadcast hash joins for small tables), and supporting iterative processing.

### 6.3 Stream Processing Principles

- **Event sourcing**: Store immutable events as the source of truth. Derive all state from the event log. "The database is a cache of a subset of the log."
- **Change Data Capture (CDC)**: Capture changes from a database's write-ahead log and publish them as a stream. This is how you keep derived systems in sync without dual writes.
- **Stream Joins**:
  - **Stream-Stream (Window Join)**: Join two event streams within a time window (e.g., correlate clicks with searches).
  - **Stream-Table (Enrichment)**: Enrich stream events with data from a slowly-changing table (e.g., add user profile to activity events).
  - **Table-Table (Materialized View)**: Maintain a materialized view as both input tables change (e.g., Twitter timeline cache).

- **Windowing**:
  - **Tumbling**: Fixed-size, non-overlapping (e.g., every 1 minute).
  - **Hopping**: Fixed-size, overlapping (e.g., 5-minute window every 1 minute).
  - **Sliding**: All events within a fixed interval of each other.
  - **Session**: Grouped by user activity with inactivity gaps.

- **Event Time vs. Processing Time**: ALWAYS use event timestamps for windowing, not the processing clock. Handle stragglers with watermarks or corrections.

- **Fault Tolerance**: Use microbatching (Spark Streaming) or checkpointing (Flink) for exactly-once semantics. For cross-system guarantees, use idempotent writes with operation IDs.

### 6.4 The Lambda vs. Kappa Architecture

| Architecture | Description | Pros | Cons |
|---|---|---|---|
| **Lambda** | Batch layer (accuracy) + Speed layer (low latency) + Serving layer (merge) | Handles late data, full reprocessing | Maintaining two codepaths, complex merging |
| **Kappa** | Single stream processing pipeline, reprocess by replaying the log | Simpler codebase, single pipeline | Requires robust log retention, reprocessing can be slow |

**RECOMMENDATION**: Start with Kappa. Only add a batch layer if you have requirements that fundamentally cannot be met by stream processing alone (e.g., complex ML training jobs over historical data).

---

## PHASE 7: API & SERVICE DESIGN

### 7.1 Communication Patterns

| Pattern | Mechanism | Best For |
|---|---|---|
| **REST/HTTP** | Request-response, stateless | Public APIs, CRUD operations, browser clients |
| **gRPC (Protobuf)** | Binary RPC, streaming, codegen | Internal service-to-service, low latency, polyglot |
| **GraphQL** | Client-specified queries | Mobile/frontend with varied data needs |
| **Async Messaging** | Event logs (Kafka), message queues | Decoupled services, event-driven architectures |

### 7.2 Schema Evolution

ALL APIs will change. Design for it from the start:
- **Backward compatibility**: New code can read old data.
- **Forward compatibility**: Old code can read new data (ignore unknown fields).
- Use **Avro/Protobuf** with required → optional field migrations. Never reuse field numbers.
- **Database schema**: Use expand-and-contract pattern. Add new columns as nullable, backfill, then enforce.

---

## PHASE 8: RELIABILITY & FAULT TOLERANCE

### 8.1 Failure Modes to Design For

| Failure | Mitigation |
|---|---|
| **Single node crash** | Replication, automatic failover, stateless services behind load balancer |
| **Network partition** | Decide CP vs. AP per operation. Use timeouts. Design for partial failures. |
| **Datacenter outage** | Multi-datacenter replication (async). DNS failover. |
| **Correlated failures** (bad deploy) | Canary deployments, feature flags, automated rollback |
| **Cascading failures** | Circuit breakers, bulkheads, backpressure, rate limiting, load shedding |
| **Byzantine faults** | Generally ignore for internal systems. Use checksums for data corruption. |
| **Clock skew** | Use logical clocks (Lamport/vector) for ordering. NTP for approximate wall-clock. Never trust wall-clock for distributed ordering. |
| **Split brain** | Fencing tokens, consensus-based leader election |

### 8.2 The End-to-End Argument

Reliability mechanisms at lower levels (TCP retries, database transactions) are necessary but NOT sufficient. You must also verify correctness end-to-end:
- **Idempotency keys**: Every mutating API request should carry a client-generated idempotency key. The server deduplicates.
- **End-to-end checksums**: Verify data integrity from producer to consumer.
- **Audit trails**: Maintain an immutable log of all state changes for debugging and recovery.

---

## PHASE 9: PERFORMANCE OPTIMIZATION

### 9.1 Caching Strategy

| Layer | Technology | TTL Strategy |
|---|---|---|
| **Client-side** | Browser cache, CDN | Cache-Control headers, ETag |
| **CDN** | CloudFront, Cloudflare | Static assets: long TTL. Dynamic: short TTL + invalidation. |
| **Application** | Redis, Memcached | Write-through, Write-behind, or Cache-aside |
| **Database** | Query cache, buffer pool | Managed by DB engine |

**Cache Invalidation Patterns**:
- **Cache-aside (Lazy Loading)**: App checks cache → miss → read DB → write cache. Simple but stale data risk.
- **Write-through**: Write to cache AND DB on every write. Consistent but higher write latency.
- **Write-behind**: Write to cache, async flush to DB. Fast writes but data loss risk.
- **Refresh-ahead**: Proactively refresh cache before expiration. Best for predictable access patterns.

**RULE**: "There are only two hard things in computer science: cache invalidation and naming things." Use CDC-based cache invalidation for strong consistency — subscribe to database change stream and invalidate/update cache entries.

### 9.2 Performance Metrics

- Measure **percentiles**, not averages. p50 for typical, p99 for tail latency.
- **Tail latency amplification**: In fan-out architectures (single request → many backend calls), the overall response time is dominated by the slowest call. A p99 latency on individual services becomes a much worse overall p99.
- **Head-of-line blocking**: A single slow request can block all subsequent requests on the same connection. Use connection pooling and async I/O.

---

## PHASE 10: SYSTEM COMPOSITION — THE "UNBUNDLED DATABASE"

### 10.1 Core Architectural Pattern

For any non-trivial system at scale, you will compose multiple specialized data systems:

```
[System of Record] --CDC/Event Log--> [Derived System 1: Search Index]
                                  +--> [Derived System 2: Cache]
                                  +--> [Derived System 3: Analytics Warehouse]
                                  +--> [Derived System 4: ML Feature Store]
```

- The **event log** (Kafka) is the backbone connecting all systems.
- Each derived system subscribes to the relevant streams and maintains its own materialized view.
- **Loose coupling**: If one derived system fails, others continue. The failed system catches up from the log on recovery.
- **Schema evolution**: Each derived system can evolve independently as long as it can read the event schema.

### 10.2 The Write Path vs. Read Path

Every data system can be understood as a boundary between:
- **Write Path** (eager): Precompute and store derived data when a write occurs.
- **Read Path** (lazy): Compute the result at query time.

Caches, indexes, and materialized views shift work from the read path to the write path. The optimal boundary depends on your read-to-write ratio and latency requirements.

### 10.3 CQRS (Command Query Responsibility Segregation)

- Separate the **write model** (optimized for correctness, normalized) from the **read model** (optimized for queries, denormalized).
- Connect them via an event log.
- This allows each side to scale independently and use different storage technologies.

---

## PHASE 11: OUTPUT — SYSTEM DESIGN DOCUMENT

For every design, produce this structured output:

### 11.1 Executive Summary
- Problem statement in 2-3 sentences.
- Key architectural decision and its justification.

### 11.2 Requirements Table
- Functional requirements (bullet list)
- Non-functional requirements (quantified table from Phase 1)

### 11.3 High-Level Architecture Diagram
- ASCII or Mermaid diagram showing:
  - Client → Load Balancer → API Gateway → Services → Data Stores
  - Message queues / event logs connecting services
  - Caching layers
  - CDN

### 11.4 Data Model
- Entity-Relationship diagram or schema definition
- Partitioning strategy and key
- Replication strategy

### 11.5 API Design
- Key endpoints with request/response shapes
- Rate limiting strategy

### 11.6 Detailed Component Design
For each major component:
- Technology choice and justification
- Scaling strategy
- Failure handling

### 11.7 Trade-Off Analysis
| Decision | Option A | Option B | Chosen | Rationale |
|---|---|---|---|---|
| Database | PostgreSQL | Cassandra | PostgreSQL | Need strong transactions for financial data |
| ... | ... | ... | ... | ... |

### 11.8 Capacity Planning
- Storage: X TB over Y years
- Compute: Z servers at N QPS each
- Network: B Gbps bandwidth
- Cost estimate (monthly)

### 11.9 Observability & Operations
- Logging strategy
- Key metrics and alerts
- Runbook for common failure scenarios

### 11.10 Evolution Strategy
- How will the system handle 10x growth?
- What are the known limitations?
- What would you change with more time?

---

## DESIGN ANTI-PATTERNS — NEVER DO THESE

| Anti-Pattern | Why It's Wrong | What To Do Instead |
|---|---|---|
| **Dual Writes** | Writing to two systems without coordination leads to inconsistency | Use CDC or event log to derive secondary systems |
| **Distributed Transactions for Everything** | 2PC is blocking, fragile, and kills performance | Use Sagas, idempotent operations, eventual consistency |
| **Premature Optimization** | Building for 1B users when you have 1K wastes engineering time | Design for 10x current load. Refactor when approaching limits. |
| **Single Global Database** | Becomes the bottleneck and single point of failure | Partition early. Use read replicas. Separate OLTP from OLAP. |
| **Ignoring Schema Evolution** | Any format change breaks consumers | Use Avro/Protobuf. Plan for forward and backward compatibility. |
| **Treating the Network as Reliable** | It's not. Ever. | Design for timeouts, retries, idempotency, and partial failures. |
| **Using Wall Clocks for Ordering** | Clocks skew. NTP is not precise enough. | Use logical clocks, version vectors, or consensus for ordering. |
| **Running Analytics on OLTP** | Kills production performance | ETL to a data warehouse. Use column-oriented storage for analytics. |

---

## REFERENCE: TECHNOLOGY SELECTION CHEAT SHEET

| Need | Primary Choice | Alternative | When to Use Alternative |
|---|---|---|---|
| **Relational DB** | PostgreSQL | MySQL, CockroachDB | MySQL: legacy/WordPress. CockroachDB: distributed SQL. |
| **Document DB** | MongoDB | CouchDB, FaunaDB | CouchDB: offline-first sync. Fauna: serverless. |
| **Wide-Column** | Apache Cassandra | ScyllaDB, HBase | ScyllaDB: higher perf. HBase: Hadoop ecosystem. |
| **Key-Value / Cache** | Redis | Memcached, DynamoDB | Memcached: simple caching. DynamoDB: managed, serverless. |
| **Search** | Elasticsearch | Meilisearch, Typesense | Meili/Typesense: simpler, smaller scale. |
| **Message Queue** | Apache Kafka | RabbitMQ, Amazon SQS | RabbitMQ: complex routing. SQS: managed, simpler. |
| **Object Storage** | Amazon S3 | GCS, MinIO | GCS: GCP ecosystem. MinIO: self-hosted. |
| **Graph DB** | Neo4j | Amazon Neptune, Dgraph | Neptune: managed AWS. Dgraph: distributed. |
| **Data Warehouse** | ClickHouse | BigQuery, Snowflake, Redshift | BigQuery: serverless. Snowflake: multi-cloud. Redshift: AWS. |
| **Stream Processing** | Apache Flink | Spark Streaming, Kafka Streams | Spark: batch + stream. Kafka Streams: lightweight, library-based. |
| **Coordination** | etcd (Raft) | ZooKeeper, Consul | ZK: mature. Consul: service discovery + KV. |
| **Container Orchestration** | Kubernetes | ECS, Docker Swarm | ECS: simpler AWS. Swarm: small deployments. |

---

## USAGE EXAMPLES

### Example 1: "Design Twitter"

**Phase 1**: 500M DAU, 600K tweets/sec read, 6K tweets/sec write, 100:1 read:write ratio, p99 < 200ms.

**Phase 2**: Tweet entity (document model), User entity, Follow graph (graph or relational for the follow table).

**Phase 3**: Fan-out on write for timeline (precompute timelines at write time for most users). Fan-out on read for celebrities (too many followers, merge at read time).

**Phase 4**: Partition tweets by user_id (hash). Replicate with single-leader async. Timeline cache is a derived data system fed by a stream processor.

**Phase 5**: Eventual consistency for timeline. Strong consistency for tweet creation (system of record).

**Phase 6**: Stream processing (Flink/Kafka Streams) to maintain timeline cache. Table-table join: tweets stream × follows stream → materialized timeline.

### Example 2: "Design a Payment System"

**Phase 1**: 50K transactions/sec peak, p99 < 500ms, 99.999% availability, zero data loss.

**Phase 2**: Relational model (PostgreSQL). Transactions, accounts, ledger entries.

**Phase 3**: B-Tree storage engine. OLTP with separate OLAP warehouse.

**Phase 4**: Single-leader replication with synchronous standby. Partition by account_id.

**Phase 5**: Serializable Snapshot Isolation. Idempotency keys on every transaction. Event sourcing for the ledger (append-only, immutable).

**Phase 6**: CDC from PostgreSQL WAL → Kafka → Analytics warehouse + Fraud detection stream processor.

**Phase 8**: Exactly-once semantics via idempotent writes. End-to-end operation IDs from client to ledger. Saga pattern for cross-service payment flows with compensating transactions.

---

## META: HOW TO THINK ABOUT SYSTEM DESIGN

1. **There is no perfect system.** Every design is a set of trade-offs. Your job is to make the trade-offs EXPLICIT and JUSTIFIED.
2. **Start simple.** A monolith with a well-chosen database is the right v1 for most products. Microservices are an organizational scaling strategy, not a technical one.
3. **Design for failure.** Everything fails. Networks, disks, clocks, humans. The question is not IF but WHEN and HOW your system handles it.
4. **Data outlives code.** Your database schema will survive many rewrites of the application. Invest heavily in data model design and schema evolution.
5. **Measure, don't guess.** Use percentiles. Profile real workloads. Load test before launch. Monitor in production.
6. **The log is the heart.** An append-only, ordered event log is the most versatile abstraction for connecting heterogeneous data systems.

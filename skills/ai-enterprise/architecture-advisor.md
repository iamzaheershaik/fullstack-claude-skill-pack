# System Architecture Advisor — Claude Skill (AI Enterprise)

> Review system designs, suggest architectural improvements, detect anti-patterns, and generate architecture blueprints from requirements. Text-based analysis with pattern matching. Node.js/TypeScript.

---

## Core Directives

1. **Patterns over opinions.** Recommend proven architectural patterns with data, not personal preference.
2. **Context drives decisions.** A startup with 2 devs and an enterprise with 50 teams need different architectures.
3. **Trade-offs, always.** Every recommendation includes what you gain and what you pay.
4. **Incremental evolution.** Suggest the simplest architecture that solves the problem. Scale when needed.

---

## 1 · Architecture Description Parser

### Structured Input Format
```typescript
interface SystemDescription {
  name: string;
  type: 'monolith' | 'microservices' | 'serverless' | 'hybrid';
  components: ComponentDef[];
  dataStores: DataStoreDef[];
  integrations: IntegrationDef[];
  constraints: { teamSize: number; budget: 'low' | 'medium' | 'high'; compliance?: string[] };
  currentPainPoints?: string[];
}

interface ComponentDef {
  name: string;
  type: 'api' | 'worker' | 'frontend' | 'gateway' | 'scheduler' | 'queue-consumer';
  language: string;
  dependencies: string[];
  traffic: 'low' | 'medium' | 'high';
  stateful: boolean;
}

interface DataStoreDef {
  name: string;
  type: 'sql' | 'nosql' | 'cache' | 'search' | 'object-storage' | 'queue';
  engine: string;
  sizeGB?: number;
  replication: boolean;
}

interface IntegrationDef {
  name: string;
  type: 'rest-api' | 'grpc' | 'webhook' | 'message-queue' | 'file-transfer';
  direction: 'inbound' | 'outbound' | 'bidirectional';
  criticality: 'low' | 'medium' | 'high';
}
```

### Auto-Parse from Code
```typescript
export function parseArchitectureFromCode(files: { path: string; content: string }[]): Partial<SystemDescription> {
  const components: ComponentDef[] = [];
  const dataStores: DataStoreDef[] = [];
  const integrations: IntegrationDef[] = [];

  for (const file of files) {
    // Detect Express/Fastify APIs
    if (/express\(\)|fastify\(\)|createServer/i.test(file.content)) {
      components.push({ name: file.path.split('/')[0] || 'api', type: 'api', language: 'typescript', dependencies: [], traffic: 'medium', stateful: false });
    }

    // Detect databases
    if (/mongoose|mongodb/i.test(file.content)) dataStores.push({ name: 'mongodb', type: 'nosql', engine: 'MongoDB', replication: false });
    if (/pg|postgres|prisma|drizzle/i.test(file.content)) dataStores.push({ name: 'postgres', type: 'sql', engine: 'PostgreSQL', replication: false });
    if (/redis|ioredis/i.test(file.content)) dataStores.push({ name: 'redis', type: 'cache', engine: 'Redis', replication: false });

    // Detect external integrations
    if (/fetch\(|axios|got\(/i.test(file.content)) {
      const urls = file.content.match(/['"]https?:\/\/[^'"]+['"]/g) || [];
      for (const url of urls) {
        integrations.push({ name: url.replace(/['"]/g, '').split('/')[2] || 'external', type: 'rest-api', direction: 'outbound', criticality: 'medium' });
      }
    }

    // Detect message queues
    if (/bullmq|amqplib|kafka|sqs/i.test(file.content)) {
      dataStores.push({ name: 'queue', type: 'queue', engine: file.content.includes('bullmq') ? 'BullMQ' : 'Other', replication: false });
    }
  }

  return { components: dedup(components, 'name'), dataStores: dedup(dataStores, 'name'), integrations };
}

function dedup<T>(arr: T[], key: keyof T): T[] {
  const seen = new Set();
  return arr.filter(item => { const k = item[key]; if (seen.has(k)) return false; seen.add(k); return true; });
}
```

---

## 2 · Anti-Pattern Detector

### Pattern Rules Engine
```typescript
interface ArchAntiPattern {
  name: string;
  severity: 'critical' | 'high' | 'medium' | 'low';
  description: string;
  detection: (sys: SystemDescription) => boolean;
  recommendation: string;
}

const ANTI_PATTERNS: ArchAntiPattern[] = [
  {
    name: 'Distributed Monolith',
    severity: 'critical',
    description: 'Microservices that are tightly coupled — all must deploy together',
    detection: (sys) => sys.type === 'microservices' && sys.components.some(c => c.dependencies.length > 3),
    recommendation: 'Reduce inter-service dependencies. Use async messaging (events) instead of sync calls.',
  },
  {
    name: 'Single Point of Failure',
    severity: 'critical',
    description: 'Critical component with no redundancy',
    detection: (sys) => sys.dataStores.some(d => d.criticality === 'high' && !d.replication),
    recommendation: 'Enable replication for critical data stores. Add failover for single-instance services.',
  },
  {
    name: 'God Service',
    severity: 'high',
    description: 'One service handling too many responsibilities',
    detection: (sys) => sys.components.some(c => c.dependencies.length > 5),
    recommendation: 'Decompose into focused services. Apply Single Responsibility Principle.',
  },
  {
    name: 'Missing Cache Layer',
    severity: 'medium',
    description: 'High-traffic reads without caching',
    detection: (sys) => sys.components.some(c => c.traffic === 'high') && !sys.dataStores.some(d => d.type === 'cache'),
    recommendation: 'Add Redis/Memcached for hot data. Cache API responses and DB query results.',
  },
  {
    name: 'Sync-Heavy Architecture',
    severity: 'medium',
    description: 'Too many synchronous inter-service calls',
    detection: (sys) => sys.integrations.filter(i => i.type === 'rest-api').length > 5 && !sys.dataStores.some(d => d.type === 'queue'),
    recommendation: 'Introduce message queue (BullMQ, SQS) for non-critical flows. Use event-driven patterns.',
  },
  {
    name: 'No API Gateway',
    severity: 'medium',
    description: 'Multiple services exposed directly to clients',
    detection: (sys) => sys.type === 'microservices' && !sys.components.some(c => c.type === 'gateway'),
    recommendation: 'Add API gateway for routing, auth, rate limiting, and request aggregation.',
  },
];

export function detectAntiPatterns(sys: SystemDescription): ArchAntiPattern[] {
  return ANTI_PATTERNS.filter(p => p.detection(sys));
}
```

---

## 3 · Architecture Advisor LLM

### Improvement Suggestions
```typescript
import OpenAI from 'openai';
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

export async function suggestImprovements(sys: SystemDescription, painPoints?: string[]): Promise<{
  suggestions: { area: string; current: string; proposed: string; effort: string; impact: string }[];
  blueprint: string;
}> {
  const response = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages: [
      {
        role: 'system',
        content: `You are a principal systems architect. Analyze the system and suggest improvements.
For each suggestion: area, current state, proposed change, effort (low/medium/high), impact (low/medium/high).
Also provide a text-based architecture blueprint (ASCII diagram).
Consider: scalability, reliability, security, cost, team capacity.
Team size: ${sys.constraints.teamSize}. Budget: ${sys.constraints.budget}.`,
      },
      {
        role: 'user',
        content: `## System\n${JSON.stringify(sys, null, 2)}\n\n${painPoints ? `## Pain Points\n${painPoints.join('\n')}` : ''}`,
      },
    ],
    max_tokens: 3000,
    temperature: 0.3,
    response_format: { type: 'json_object' },
  });

  return JSON.parse(response.choices[0].message.content || '{"suggestions":[],"blueprint":""}');
}
```

---

## 4 · Pattern Recommendation Engine

### Architecture Decision Matrix
| Scenario | Pattern | Why | When to Avoid |
|---|---|---|---|
| < 5 devs, single product | Modular Monolith | Simple deploy, fast dev | > 100k RPM on isolated features |
| Multiple teams, independent features | Microservices | Independent deploy/scale | < 3 devs, premature |
| Event-heavy, audit trail needed | Event Sourcing + CQRS | Complete history, replay | Simple CRUD apps |
| High read/low write | CQRS (read/write split) | Optimize each path | Balanced read/write |
| Bursty, unpredictable traffic | Serverless (Lambda/Functions) | Auto-scale, pay per use | Latency-sensitive |
| Real-time bidirectional | WebSocket + pub/sub | Low latency push | Request/response only |

### Scaling Decision Tree
```
Q: Is one service a bottleneck?
├─ YES → Horizontal scale (more instances) + load balancer
│   Q: Is the DB the bottleneck?
│   ├─ YES → Read replicas + connection pooling + caching
│   └─ NO → Add instances, check CPU/memory limits
└─ NO → Q: Is inter-service latency the issue?
    ├─ YES → Reduce sync calls, add async messaging
    └─ NO → Profile application code, check N+1 queries
```

### Caching Strategy Guide
| Data Type | Cache | TTL | Invalidation |
|---|---|---|---|
| User sessions | Redis | 15 min | On logout/token refresh |
| API responses | Redis/CDN | 1-5 min | On data mutation |
| DB query results | In-process/Redis | 30s-5min | On write to same table |
| Static assets | CDN | 1 year | Hash-based URL (immutable) |
| Rate limit counters | Redis | 1-15 min | Auto-expire |

---

## 5 · Blueprint Generator

### Mermaid Diagram Output
```typescript
export function generateArchDiagram(sys: SystemDescription): string {
  let diagram = 'graph TD\n';

  // Add components
  for (const c of sys.components) {
    const shape = c.type === 'frontend' ? `${c.name}[${c.name}]` : `${c.name}((${c.name}))`;
    diagram += `  ${shape}\n`;
  }

  // Add data stores
  for (const d of sys.dataStores) {
    diagram += `  ${d.name}[(${d.name} - ${d.engine})]\n`;
  }

  // Add connections
  for (const c of sys.components) {
    for (const dep of c.dependencies) {
      diagram += `  ${c.name} --> ${dep}\n`;
    }
  }

  return diagram;
}
```

---

## 6 · Architecture Advisor Checklist

```
Analysis:
✓ Auto-parse architecture from codebase
✓ Anti-pattern detection (6+ patterns)
✓ Bottleneck identification (traffic, data, coupling)
✓ Security architecture review (auth, encryption, network)

Recommendations:
✓ Pattern suggestions with trade-offs
✓ Scaling decision tree
✓ Caching strategy by data type
✓ Database selection guidance
✓ Effort/impact scoring for each suggestion

Output:
✓ Architecture diagram (Mermaid/ASCII)
✓ Anti-pattern report with severity
✓ Migration path (current → target)
✓ Cost impact estimates

Context-Aware:
✓ Team size consideration
✓ Budget constraints
✓ Compliance requirements (if applicable)
✓ Current pain points as input
```

---

## Response Format

```
1. Current architecture summary (auto-detected or described)
2. Anti-patterns detected (severity + remediation)
3. Improvement suggestions (prioritized by impact/effort)
4. Architecture diagram (Mermaid)
```

**Never output:** recommendations without trade-offs, overengineered solutions for small teams, pattern changes without migration path.
**Always output:** severity ranking, effort estimates, team-size context, diagram visualization.

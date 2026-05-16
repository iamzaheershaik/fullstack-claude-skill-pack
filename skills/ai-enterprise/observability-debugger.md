---
name: Observability & Debugging Integrator
category: ai-enterprise
version: 1.0.0
description: >
  Correlate production logs, metrics, and error traces with source code. Auto-diagnose incidents, trace root causes, and suggest fixes. Integrates with ELK, Sentry, Prometheus. Node.js/TypeScript.
author: Zaheer Shaik
tags:
  - observability
  - debugging
  - monitoring
  - ai
  - enterprise
---

# Observability & Debugging Integrator — Claude Skill (AI Enterprise)

> Correlate production logs, metrics, and error traces with source code. Auto-diagnose incidents, trace root causes, and suggest fixes. Integrates with ELK, Sentry, Prometheus. Node.js/TypeScript.

---

## Core Directives

1. **Code-first diagnosis.** Every log error maps back to a file:line in the codebase.
2. **Reduce MTTR.** Get from alert to root cause in minutes, not hours.
3. **Structured everything.** Logs, metrics, traces — all structured, all correlated by request ID.
4. **Privacy-safe.** Strip PII from logs before analysis. Never expose user data.

---

## 1 · Log Ingestion & Parsing

### Structured Log Parser
```typescript
interface ParsedLog {
  timestamp: Date;
  level: 'error' | 'warn' | 'info' | 'debug';
  message: string;
  requestId?: string;
  userId?: string;
  service?: string;
  error?: { name: string; message: string; stack: string };
  metadata: Record<string, any>;
}

export function parseLogEntry(raw: string): ParsedLog | null {
  // JSON structured logs
  try {
    const json = JSON.parse(raw);
    return {
      timestamp: new Date(json.timestamp || json.time || json.ts),
      level: normalizeLevel(json.level || json.severity),
      message: json.message || json.msg,
      requestId: json.requestId || json.correlationId || json.traceId,
      userId: json.userId,
      service: json.service || json.app,
      error: json.err || json.error ? {
        name: json.err?.name || json.error?.name || 'Error',
        message: json.err?.message || json.error?.message || '',
        stack: json.err?.stack || json.error?.stack || '',
      } : undefined,
      metadata: json,
    };
  } catch {
    // Unstructured fallback
    const match = raw.match(/\[(\w+)\]\s*(.+)/);
    if (match) {
      return { timestamp: new Date(), level: normalizeLevel(match[1]), message: match[2], metadata: {} };
    }
    return null;
  }
}

function normalizeLevel(level: string): ParsedLog['level'] {
  const l = level.toLowerCase();
  if (['error', 'fatal', 'critical'].includes(l)) return 'error';
  if (['warn', 'warning'].includes(l)) return 'warn';
  if (['debug', 'trace'].includes(l)) return 'debug';
  return 'info';
}
```

### PII Scrubber
```typescript
const PII_PATTERNS = [
  { name: 'email', regex: /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g, replacement: '[EMAIL]' },
  { name: 'phone', regex: /\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/g, replacement: '[PHONE]' },
  { name: 'ssn', regex: /\b\d{3}-\d{2}-\d{4}\b/g, replacement: '[SSN]' },
  { name: 'credit-card', regex: /\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/g, replacement: '[CC]' },
  { name: 'ip', regex: /\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/g, replacement: '[IP]' },
  { name: 'jwt', regex: /eyJ[a-zA-Z0-9_-]+\.eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+/g, replacement: '[JWT]' },
];

export function scrubPII(text: string): string {
  let clean = text;
  for (const pattern of PII_PATTERNS) {
    clean = clean.replace(pattern.regex, pattern.replacement);
  }
  return clean;
}
```

---

## 2 · Stack Trace → Code Mapper

### Stack Trace Parser
```typescript
interface StackFrame {
  file: string;
  line: number;
  column: number;
  function: string;
  isInternal: boolean; // node_modules or node internals
}

export function parseStackTrace(stack: string): StackFrame[] {
  const frames: StackFrame[] = [];
  const lines = stack.split('\n');

  for (const line of lines) {
    const match = line.match(/at\s+(?:(.+?)\s+\()?((?:\/|[A-Z]:).+?):(\d+):(\d+)\)?/);
    if (match) {
      frames.push({
        function: match[1] || '<anonymous>',
        file: match[2],
        line: parseInt(match[3]),
        column: parseInt(match[4]),
        isInternal: match[2].includes('node_modules') || match[2].includes('node:'),
      });
    }
  }

  return frames;
}

export function getApplicationFrames(frames: StackFrame[]): StackFrame[] {
  return frames.filter(f => !f.isInternal);
}
```

### Source Code Lookup
```typescript
import { readFileSync, existsSync } from 'fs';

export function getCodeContext(frame: StackFrame, contextLines = 5): {
  frame: StackFrame;
  code: string;
  highlightLine: number;
} | null {
  if (!existsSync(frame.file)) return null;

  const content = readFileSync(frame.file, 'utf-8');
  const lines = content.split('\n');
  const start = Math.max(0, frame.line - contextLines - 1);
  const end = Math.min(lines.length, frame.line + contextLines);

  const code = lines.slice(start, end).map((l, i) => {
    const lineNum = start + i + 1;
    const marker = lineNum === frame.line ? '>>>' : '   ';
    return `${marker} ${lineNum}: ${l}`;
  }).join('\n');

  return { frame, code, highlightLine: frame.line };
}
```

---

## 3 · Error Fingerprinting & Grouping

### Error Fingerprint Generator
```typescript
import { createHash } from 'crypto';

interface ErrorGroup {
  fingerprint: string;
  count: number;
  firstSeen: Date;
  lastSeen: Date;
  samples: ParsedLog[];
  appFrames: StackFrame[];
}

export function fingerprint(log: ParsedLog): string {
  const parts = [
    log.error?.name || 'Error',
    log.error?.message?.replace(/\b[0-9a-f-]{36}\b/g, '{id}').replace(/\d+/g, '{n}') || '',
    log.service || '',
  ];

  if (log.error?.stack) {
    const frames = getApplicationFrames(parseStackTrace(log.error.stack));
    if (frames.length) parts.push(`${frames[0].file}:${frames[0].function}`);
  }

  return createHash('md5').update(parts.join('|')).digest('hex').slice(0, 12);
}

export function groupErrors(logs: ParsedLog[]): Map<string, ErrorGroup> {
  const groups = new Map<string, ErrorGroup>();

  for (const log of logs.filter(l => l.level === 'error')) {
    const fp = fingerprint(log);
    const existing = groups.get(fp);

    if (existing) {
      existing.count++;
      existing.lastSeen = log.timestamp;
      if (existing.samples.length < 3) existing.samples.push(log);
    } else {
      const frames = log.error?.stack ? getApplicationFrames(parseStackTrace(log.error.stack)) : [];
      groups.set(fp, { fingerprint: fp, count: 1, firstSeen: log.timestamp, lastSeen: log.timestamp, samples: [log], appFrames: frames });
    }
  }

  return groups;
}
```

---

## 4 · AI Diagnosis Engine

### Root Cause Analyzer
```typescript
import OpenAI from 'openai';
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

interface Diagnosis {
  rootCause: string;
  confidence: 'high' | 'medium' | 'low';
  affectedFiles: { file: string; line: number; issue: string }[];
  suggestedFix: string;
  preventionTip: string;
  relatedPatterns: string[];
}

export async function diagnoseError(
  errorGroup: ErrorGroup,
  codeContext: { frame: StackFrame; code: string }[],
  recentChanges?: string,
): Promise<Diagnosis> {
  const response = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages: [
      {
        role: 'system',
        content: `You are a senior SRE and debugger. Diagnose the error from logs, stack trace, and source code.
Return JSON:
{
  "rootCause": "clear explanation of why the error occurs",
  "confidence": "high|medium|low",
  "affectedFiles": [{"file": string, "line": number, "issue": string}],
  "suggestedFix": "code change or config fix",
  "preventionTip": "how to prevent this class of error",
  "relatedPatterns": ["similar known error patterns"]
}`,
      },
      {
        role: 'user',
        content: `## Error (${errorGroup.count} occurrences)
Name: ${errorGroup.samples[0].error?.name}
Message: ${scrubPII(errorGroup.samples[0].error?.message || '')}
Service: ${errorGroup.samples[0].service}

## Stack Trace (app frames)
${errorGroup.appFrames.map(f => `${f.file}:${f.line} in ${f.function}`).join('\n')}

## Source Code Context
${codeContext.map(c => `### ${c.frame.file}:${c.frame.line}\n\`\`\`\n${c.code}\n\`\`\``).join('\n\n')}

${recentChanges ? `## Recent Changes\n${recentChanges}` : ''}`,
      },
    ],
    max_tokens: 1500,
    temperature: 0.2,
    response_format: { type: 'json_object' },
  });

  return JSON.parse(response.choices[0].message.content || '{}');
}
```

---

## 5 · Alert Integration

### Sentry Webhook Handler
```typescript
import express from 'express';
const app = express();

app.post('/webhook/sentry', express.json(), async (req, res) => {
  const { event, project } = req.body;

  if (event?.exception?.values) {
    const error = event.exception.values[0];
    const log: ParsedLog = {
      timestamp: new Date(event.timestamp * 1000),
      level: 'error',
      message: error.value,
      service: project?.slug,
      error: { name: error.type, message: error.value, stack: formatSentryStack(error.stacktrace) },
      requestId: event.contexts?.trace?.trace_id,
      metadata: event.tags || {},
    };

    const fp = fingerprint(log);
    // 1. Group with existing errors
    // 2. Get code context
    // 3. Run AI diagnosis
    // 4. Post to Slack/Teams
    await handleNewError(log, fp);
  }

  res.status(200).send('OK');
});

function formatSentryStack(stacktrace: any): string {
  if (!stacktrace?.frames) return '';
  return stacktrace.frames.reverse().map((f: any) =>
    `    at ${f.function || '<anonymous>'} (${f.filename}:${f.lineno}:${f.colno})`
  ).join('\n');
}
```

### Slack Alert Formatter
```typescript
export function formatSlackAlert(errorGroup: ErrorGroup, diagnosis: Diagnosis): object {
  return {
    blocks: [
      { type: 'header', text: { type: 'plain_text', text: `🚨 ${errorGroup.samples[0].error?.name}: ${errorGroup.samples[0].error?.message?.slice(0, 80)}` } },
      { type: 'section', fields: [
        { type: 'mrkdwn', text: `*Occurrences:* ${errorGroup.count}` },
        { type: 'mrkdwn', text: `*Service:* ${errorGroup.samples[0].service}` },
        { type: 'mrkdwn', text: `*Confidence:* ${diagnosis.confidence}` },
        { type: 'mrkdwn', text: `*First:* ${errorGroup.firstSeen.toISOString()}` },
      ]},
      { type: 'section', text: { type: 'mrkdwn', text: `*Root Cause:* ${diagnosis.rootCause}` } },
      { type: 'section', text: { type: 'mrkdwn', text: `*Suggested Fix:*\n\`\`\`${diagnosis.suggestedFix}\`\`\`` } },
      { type: 'section', text: { type: 'mrkdwn', text: `*Files:* ${diagnosis.affectedFiles.map(f => `\`${f.file}:${f.line}\``).join(', ')}` } },
    ],
  };
}
```

---

## 6 · Common Error Pattern Database

| Error Pattern | Root Cause | Fix |
|---|---|---|
| `ECONNREFUSED` | Service/DB down or wrong port | Check service health, verify connection string |
| `ETIMEOUT` | Upstream too slow | Add timeout, circuit breaker, retry |
| `MongoNetworkError` | MongoDB connection lost | Connection pooling, retry logic, replica set |
| `JWT malformed` | Invalid/expired token | Check token format, refresh flow |
| `ENOMEM` | Memory leak or insufficient limits | Profile heap, increase limits, check for leaks |
| `ENOSPC` | Disk full | Log rotation, clean temp files, increase volume |
| `UnhandledPromiseRejection` | Missing .catch() or try/catch | Add error handling on all async paths |
| `ERR_HTTP_HEADERS_SENT` | Double response in handler | Ensure single res.send(), use return |

---

## 7 · MTTR Tracking

### Incident Schema
```typescript
import { Schema, model } from 'mongoose';

const incidentSchema = new Schema({
  fingerprint: { type: String, required: true, index: true },
  service: String,
  errorName: String,
  errorMessage: String,
  occurrences: { type: Number, default: 1 },
  firstSeen: { type: Date, required: true },
  resolvedAt: Date,
  mttrMinutes: Number,
  diagnosis: {
    rootCause: String,
    confidence: String,
    suggestedFix: String,
    aiAssisted: { type: Boolean, default: true },
  },
  resolvedBy: String,
});

export const Incident = model('Incident', incidentSchema);
```

---

## 8 · Observability Checklist

```
Log Processing:     ✓ JSON logs (Pino/Winston) · ✓ Unstructured fallback · ✓ PII scrubbing · ✓ Request ID correlation
Error Analysis:     ✓ Stack→code mapping · ✓ Fingerprinting/grouping · ✓ Frequency tracking · ✓ AI root cause
Integration:        ✓ Sentry webhook · ✓ Slack/Teams alerts · ✓ MTTR tracking · ✓ Pattern database
Quality:            ✓ Confidence scoring · ✓ Code context (±5 lines) · ✓ Git changes correlation · ✓ Feedback loop
Security:           ✗ Never analyze PII · ✓ Scrub before LLM · ✓ Audit trail · ✓ Access control
```

---

## Response Format

Output: (1) Error summary (name, message, frequency, service) → (2) Stack trace + source context → (3) AI diagnosis (root cause, confidence, files) → (4) Suggested fix → (5) Prevention tip.

**Never output:** raw PII, diagnosis without confidence level, fixes without file references.
**Always output:** error fingerprint, occurrence count, code context, remediation steps, MTTR data.

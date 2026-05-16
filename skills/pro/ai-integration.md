---
name: AI Integration
category: pro
version: 1.0.0
description: >
  Integrate AI into production apps. OpenAI/Claude APIs, streaming, RAG, embeddings, vector search, prompt engineering, and cost optimization. Node.js.
author: Zaheer Shaik
tags:
  - ai
  - openai
  - rag
  - embeddings
  - pro
---

# AI Integration — Claude Skill (Pro)

> Integrate AI into production apps. OpenAI/Claude APIs, streaming, RAG, embeddings, vector search, prompt engineering, cost optimization. Node.js.

---

## Core Directives

1. **AI is a feature, not the product.** Wrap AI calls in services with fallbacks.
2. **Stream by default.** Users expect instant feedback — stream tokens, don't wait.
3. **Guard your wallet.** Set hard token limits, cache responses, use cheaper models for simple tasks.
4. **Prompt is code.** Version it, test it, review it — prompt changes are deployments.

---

## 1 · API Client Setup

### OpenAI
```typescript
import OpenAI from 'openai';

export const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

export async function chatCompletion(messages: OpenAI.ChatCompletionMessageParam[], options?: {
  model?: string;
  maxTokens?: number;
  temperature?: number;
}) {
  const response = await openai.chat.completions.create({
    model: options?.model || 'gpt-4o-mini',
    messages,
    max_tokens: options?.maxTokens || 1000,
    temperature: options?.temperature ?? 0.7,
  });

  return {
    content: response.choices[0].message.content,
    usage: response.usage,
    model: response.model,
  };
}
```

### Claude (Anthropic)
```typescript
import Anthropic from '@anthropic-ai/sdk';

export const claude = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

export async function claudeCompletion(prompt: string, options?: {
  model?: string;
  maxTokens?: number;
  system?: string;
}) {
  const response = await claude.messages.create({
    model: options?.model || 'claude-sonnet-4-20250514',
    max_tokens: options?.maxTokens || 1000,
    system: options?.system,
    messages: [{ role: 'user', content: prompt }],
  });

  return {
    content: response.content[0].type === 'text' ? response.content[0].text : '',
    usage: response.usage,
    model: response.model,
  };
}
```

---

## 2 · Streaming Responses

### Server (Express + SSE)
```typescript
router.post('/ai/chat', authenticate, async (req, res) => {
  const { messages, model } = req.body;

  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');

  const stream = await openai.chat.completions.create({
    model: model || 'gpt-4o-mini',
    messages,
    max_tokens: 2000,
    stream: true,
  });

  let totalTokens = 0;

  for await (const chunk of stream) {
    const content = chunk.choices[0]?.delta?.content;
    if (content) {
      res.write(`data: ${JSON.stringify({ content })}\n\n`);
    }
    if (chunk.usage) totalTokens = chunk.usage.total_tokens;
  }

  res.write(`data: ${JSON.stringify({ done: true, usage: { totalTokens } })}\n\n`);
  res.end();

  // Track usage
  await incrementUsage(req.org.id, 'ai_tokens', totalTokens);
});
```

### Client (React)
```typescript
export async function streamChat(
  messages: Message[],
  onChunk: (text: string) => void,
  onDone: () => void,
) {
  const response = await fetch('/api/v1/ai/chat', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${getToken()}`,
    },
    body: JSON.stringify({ messages }),
  });

  const reader = response.body!.getReader();
  const decoder = new TextDecoder();

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    const text = decoder.decode(value);
    const lines = text.split('\n').filter(l => l.startsWith('data: '));

    for (const line of lines) {
      const data = JSON.parse(line.slice(6));
      if (data.done) { onDone(); return; }
      if (data.content) onChunk(data.content);
    }
  }
}

// React hook
function useChatStream() {
  const [response, setResponse] = useState('');
  const [isStreaming, setIsStreaming] = useState(false);

  const send = async (messages: Message[]) => {
    setResponse('');
    setIsStreaming(true);
    await streamChat(
      messages,
      (chunk) => setResponse(prev => prev + chunk),
      () => setIsStreaming(false),
    );
  };

  return { response, isStreaming, send };
}
```

---

## 3 · RAG (Retrieval-Augmented Generation)

### Architecture
```
1. INGEST: Document → chunk → embed → store in vector DB
2. QUERY:  User question → embed → search vectors → top-K results
3. GENERATE: System prompt + context chunks + user question → LLM → answer
```

### Embedding & Storage
```typescript
// Generate embeddings
export async function generateEmbedding(text: string): Promise<number[]> {
  const response = await openai.embeddings.create({
    model: 'text-embedding-3-small',
    input: text,
  });
  return response.data[0].embedding;
}

// MongoDB Atlas Vector Search (or use Pinecone/Weaviate)
const documentChunkSchema = new Schema({
  org: { type: Types.ObjectId, ref: 'Org', required: true },
  source: { type: String, required: true }, // file name or URL
  content: { type: String, required: true },
  embedding: { type: [Number], required: true },
  metadata: {
    pageNumber: Number,
    chunkIndex: Number,
    tokenCount: Number,
  },
});

// Atlas Vector Search index (create in Atlas UI):
// { "fields": [{ "type": "vector", "path": "embedding", "numDimensions": 1536, "similarity": "cosine" }] }
```

### Chunking Strategy
```typescript
export function chunkText(text: string, options = { maxTokens: 500, overlap: 50 }): string[] {
  const sentences = text.split(/(?<=[.!?])\s+/);
  const chunks: string[] = [];
  let current = '';

  for (const sentence of sentences) {
    if (estimateTokens(current + sentence) > options.maxTokens) {
      if (current) chunks.push(current.trim());
      // Overlap: keep last N tokens from previous chunk
      const words = current.split(' ');
      current = words.slice(-options.overlap).join(' ') + ' ' + sentence;
    } else {
      current += ' ' + sentence;
    }
  }
  if (current.trim()) chunks.push(current.trim());

  return chunks;
}

function estimateTokens(text: string): number {
  return Math.ceil(text.length / 4); // rough estimate
}
```

### Vector Search & Answer
```typescript
export async function ragQuery(orgId: string, question: string) {
  const queryEmbedding = await generateEmbedding(question);

  // Vector search
  const results = await DocumentChunk.aggregate([
    {
      $vectorSearch: {
        index: 'vector_index',
        path: 'embedding',
        queryVector: queryEmbedding,
        numCandidates: 100,
        limit: 5,
        filter: { org: new Types.ObjectId(orgId) },
      },
    },
    { $project: { content: 1, source: 1, score: { $meta: 'vectorSearchScore' } } },
  ]);

  // Build context
  const context = results.map(r => r.content).join('\n\n---\n\n');

  // Generate answer
  const response = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      {
        role: 'system',
        content: `Answer based on the provided context. If the context doesn't contain the answer, say so. Cite sources.
        
Context:
${context}`,
      },
      { role: 'user', content: question },
    ],
    max_tokens: 1000,
    temperature: 0.3,
  });

  return {
    answer: response.choices[0].message.content,
    sources: results.map(r => ({ source: r.source, score: r.score })),
    usage: response.usage,
  };
}
```

---

## 4 · Prompt Management

### Prompt Templates
```typescript
const PROMPTS = {
  summarize: {
    system: 'You are a professional summarizer. Be concise and accurate.',
    user: 'Summarize the following text in {{length}} sentences:\n\n{{text}}',
    model: 'gpt-4o-mini',
    maxTokens: 500,
  },
  extractData: {
    system: 'Extract structured data from text. Return valid JSON only.',
    user: 'Extract the following fields from this text: {{fields}}\n\nText: {{text}}',
    model: 'gpt-4o-mini',
    maxTokens: 1000,
    temperature: 0,
  },
} as const;

export function buildPrompt(template: keyof typeof PROMPTS, vars: Record<string, string>) {
  const prompt = PROMPTS[template];
  let userMsg = prompt.user;
  for (const [key, value] of Object.entries(vars)) {
    userMsg = userMsg.replace(`{{${key}}}`, value);
  }
  return { ...prompt, user: userMsg };
}
```

---

## 5 · Cost Optimization

### Model Selection
| Task | Model | Cost/1M tokens |
|---|---|---|
| Simple classification | gpt-4o-mini | $0.15 |
| General chat | gpt-4o-mini | $0.15 |
| Complex reasoning | gpt-4o | $2.50 |
| Embeddings | text-embedding-3-small | $0.02 |
| Code generation | claude-sonnet | ~$3.00 |

### Cost Controls
```typescript
// Per-request token limit
const MAX_TOKENS_PER_REQUEST = 4000;

// Per-org daily limit
const DAILY_TOKEN_LIMITS = {
  free: 10_000,
  starter: 100_000,
  pro: 1_000_000,
};

// Check before calling AI
export async function checkAIBudget(orgId: string, estimatedTokens: number) {
  const today = new Date().toISOString().slice(0, 10);
  const usage = await Usage.findOne({ org: orgId, resource: 'ai_tokens', period: today });
  const plan = (await Org.findById(orgId)).plan;
  const limit = DAILY_TOKEN_LIMITS[plan];

  if ((usage?.count || 0) + estimatedTokens > limit) {
    throw new AppError(429, 'AI_LIMIT', 'Daily AI usage limit reached. Upgrade for more.');
  }
}

// Cache repeated queries
const cache = new Map<string, { result: string; expiry: number }>();

export async function cachedCompletion(key: string, messages: any[], ttlMs = 3600000) {
  const cached = cache.get(key);
  if (cached && cached.expiry > Date.now()) return cached.result;

  const result = await chatCompletion(messages);
  cache.set(key, { result: result.content, expiry: Date.now() + ttlMs });
  return result.content;
}
```

---

## 6 · AI Integration Checklist

```
API:
✓ API keys in env vars (never client-side)
✓ Server-side proxy for all AI calls
✓ Streaming for chat/generation endpoints
✓ Token usage tracking per org
✓ Rate limiting and budget caps

RAG:
✓ Chunk documents (300-500 tokens per chunk)
✓ Overlap chunks by 10-15%
✓ Store embeddings with tenant isolation
✓ Use vector search with org filter
✓ Cite sources in responses

Cost:
✓ Use cheapest model that works (gpt-4o-mini first)
✓ Cache repeated queries
✓ Set per-request and per-org token limits
✓ Monitor daily spend
✓ Alert on unusual usage spikes

Security:
✗ Never expose API keys to frontend
✗ Never pass unsanitized user input to system prompts
✗ Never log full prompts (may contain PII)
✓ Sanitize AI output before rendering (prevent XSS)
```

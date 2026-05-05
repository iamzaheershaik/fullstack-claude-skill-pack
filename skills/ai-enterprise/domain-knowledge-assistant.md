# Domain Knowledge-Infused Assistant — Claude Skill (AI Enterprise)

> Load company-specific docs, business rules, API specs, and policies into RAG context. Generate code that respects domain constraints and internal conventions. Node.js/TypeScript.

---

## Core Directives

1. **Domain rules are law.** Generated code must comply with loaded business rules — never override with generic patterns.
2. **Cite your sources.** Every domain-informed suggestion includes the document and section it came from.
3. **Ask when uncertain.** If domain docs are ambiguous, flag the gap — don't guess.
4. **Separate domain from infra.** Domain logic in service layer; never mix business rules with framework code.

---

## 1 · Document Ingestion Pipeline

### Multi-Format Loader
```typescript
import { readFileSync } from 'fs';
import pdf from 'pdf-parse';
import mammoth from 'mammoth';
import { marked } from 'marked';

interface IngestedDoc {
  source: string;
  format: 'pdf' | 'docx' | 'md' | 'txt' | 'html';
  content: string;
  metadata: { title?: string; author?: string; lastModified?: Date };
}

export async function ingestDocument(filePath: string): Promise<IngestedDoc> {
  const ext = filePath.split('.').pop()?.toLowerCase();

  switch (ext) {
    case 'pdf': {
      const buffer = readFileSync(filePath);
      const data = await pdf(buffer);
      return { source: filePath, format: 'pdf', content: data.text, metadata: { title: data.info?.Title } };
    }
    case 'docx': {
      const result = await mammoth.extractRawText({ path: filePath });
      return { source: filePath, format: 'docx', content: result.value, metadata: {} };
    }
    case 'md': {
      const raw = readFileSync(filePath, 'utf-8');
      return { source: filePath, format: 'md', content: raw, metadata: {} };
    }
    default: {
      const content = readFileSync(filePath, 'utf-8');
      return { source: filePath, format: 'txt', content, metadata: {} };
    }
  }
}
```

### Semantic Chunker
```typescript
interface DocChunk {
  id: string;
  source: string;
  section: string;
  content: string;
  tokenCount: number;
}

export function chunkDocument(doc: IngestedDoc, maxTokens = 500, overlap = 50): DocChunk[] {
  const sections = splitBySections(doc.content);
  const chunks: DocChunk[] = [];

  for (const section of sections) {
    const sentences = section.content.split(/(?<=[.!?])\s+/);
    let current = '';
    let chunkIdx = 0;

    for (const sentence of sentences) {
      if (estimateTokens(current + sentence) > maxTokens) {
        if (current) {
          chunks.push({
            id: `${doc.source}::${section.title}::${chunkIdx}`,
            source: doc.source,
            section: section.title,
            content: current.trim(),
            tokenCount: estimateTokens(current),
          });
          chunkIdx++;
          const words = current.split(' ');
          current = words.slice(-overlap).join(' ') + ' ' + sentence;
        }
      } else {
        current += ' ' + sentence;
      }
    }
    if (current.trim()) {
      chunks.push({ id: `${doc.source}::${section.title}::${chunkIdx}`, source: doc.source, section: section.title, content: current.trim(), tokenCount: estimateTokens(current) });
    }
  }
  return chunks;
}

function splitBySections(text: string): { title: string; content: string }[] {
  const parts = text.split(/^(#{1,3}\s+.+)$/m);
  const sections: { title: string; content: string }[] = [];
  for (let i = 0; i < parts.length; i++) {
    if (parts[i].startsWith('#')) {
      sections.push({ title: parts[i].replace(/^#+\s+/, ''), content: parts[i + 1] || '' });
      i++;
    } else if (i === 0 && parts[i].trim()) {
      sections.push({ title: 'Overview', content: parts[i] });
    }
  }
  return sections.length ? sections : [{ title: 'Document', content: text }];
}

function estimateTokens(text: string): number { return Math.ceil(text.length / 4); }
```

---

## 2 · Domain Vector Store

### Schema
```typescript
import { Schema, model } from 'mongoose';

const domainChunkSchema = new Schema({
  org: { type: String, required: true, index: true },
  source: { type: String, required: true },
  section: { type: String },
  content: { type: String, required: true },
  embedding: { type: [Number], required: true },
  category: { type: String, enum: ['policy', 'api-spec', 'business-rule', 'glossary', 'guide'] },
  lastUpdated: { type: Date, default: Date.now },
});

export const DomainChunk = model('DomainChunk', domainChunkSchema);
// Atlas Vector Search index on 'embedding' field
```

### Ingestion Workflow
```typescript
import OpenAI from 'openai';
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

export async function ingestAndIndex(orgId: string, filePath: string, category: string) {
  const doc = await ingestDocument(filePath);
  const chunks = chunkDocument(doc);

  // Generate embeddings in batches
  const embeddings: number[][] = [];
  for (let i = 0; i < chunks.length; i += 100) {
    const batch = chunks.slice(i, i + 100);
    const resp = await openai.embeddings.create({
      model: 'text-embedding-3-small',
      input: batch.map(c => c.content),
    });
    embeddings.push(...resp.data.map(d => d.embedding));
  }

  // Upsert into vector store
  const ops = chunks.map((chunk, i) => ({
    updateOne: {
      filter: { org: orgId, source: chunk.source, section: chunk.section },
      update: { $set: { content: chunk.content, embedding: embeddings[i], category, lastUpdated: new Date() } },
      upsert: true,
    },
  }));
  await DomainChunk.bulkWrite(ops);

  return { chunksIndexed: chunks.length, source: filePath };
}
```

---

## 3 · Domain-Aware Query Router

### Query Classification
```typescript
interface QueryIntent {
  needsDomainContext: boolean;
  domainCategories: string[];
  codeGeneration: boolean;
  query: string;
}

export async function classifyQuery(query: string): Promise<QueryIntent> {
  const response = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      {
        role: 'system',
        content: `Classify this developer query. Return JSON:
{ "needsDomainContext": bool, "domainCategories": ["policy"|"api-spec"|"business-rule"|"glossary"|"guide"], "codeGeneration": bool, "query": "cleaned query" }
Domain context needed if query mentions: business rules, policies, company-specific APIs, compliance, internal naming.`,
      },
      { role: 'user', content: query },
    ],
    max_tokens: 200,
    temperature: 0,
    response_format: { type: 'json_object' },
  });

  return JSON.parse(response.choices[0].message.content || '{}');
}
```

### Context Retrieval
```typescript
export async function retrieveDomainContext(orgId: string, query: string, categories?: string[], topK = 5) {
  const [qEmbed] = await Promise.all([
    openai.embeddings.create({ model: 'text-embedding-3-small', input: [query] }),
  ]);

  const filter: any = { org: orgId };
  if (categories?.length) filter.category = { $in: categories };

  const results = await DomainChunk.aggregate([
    {
      $vectorSearch: {
        index: 'domain_vector_index', path: 'embedding',
        queryVector: qEmbed.data[0].embedding,
        numCandidates: topK * 10, limit: topK,
        filter,
      },
    },
    { $project: { content: 1, source: 1, section: 1, category: 1, score: { $meta: 'vectorSearchScore' } } },
  ]);

  return results;
}
```

---

## 4 · Domain-Aligned Code Generation

### Code Generator with Domain Context
```typescript
export async function generateDomainCode(
  orgId: string,
  prompt: string,
  codeContext?: string,
): Promise<{ code: string; domainSources: { source: string; section: string }[]; warnings: string[] }> {
  const intent = await classifyQuery(prompt);
  let domainContext = '';
  let sources: { source: string; section: string }[] = [];

  if (intent.needsDomainContext) {
    const docs = await retrieveDomainContext(orgId, prompt, intent.domainCategories);
    domainContext = docs.map(d => `[${d.category}] ${d.section} (${d.source}):\n${d.content}`).join('\n\n---\n\n');
    sources = docs.map(d => ({ source: d.source, section: d.section }));
  }

  const response = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages: [
      {
        role: 'system',
        content: `You are a senior engineer with deep knowledge of this organization's domain.
${domainContext ? `\n## Domain Knowledge\n${domainContext}\n` : ''}
Rules:
- Generated code MUST comply with all domain rules and policies cited above
- Use domain-specific terminology in variable/function names
- Flag any conflicts between request and domain rules as warnings
- Cite which domain document informed each decision`,
      },
      {
        role: 'user',
        content: codeContext ? `## Existing Code\n\`\`\`\n${codeContext}\n\`\`\`\n\n## Request\n${prompt}` : prompt,
      },
    ],
    max_tokens: 3000,
    temperature: 0.2,
  });

  const code = response.choices[0].message.content || '';
  const warnings = extractWarnings(code);

  return { code, domainSources: sources, warnings };
}

function extractWarnings(output: string): string[] {
  const warnings: string[] = [];
  const regex = /(?:WARNING|CAUTION|NOTE|⚠️):?\s*(.+)/gi;
  let m;
  while ((m = regex.exec(output))) warnings.push(m[1]);
  return warnings;
}
```

---

## 5 · Glossary & Naming Enforcer

### Domain Glossary Schema
```typescript
const glossarySchema = new Schema({
  org: { type: String, required: true },
  term: { type: String, required: true },
  definition: { type: String, required: true },
  preferredCodeName: { type: String }, // e.g. "customerLifetimeValue" for "CLV"
  aliases: [String],
  category: String,
});

export const Glossary = model('Glossary', glossarySchema);
```

### Naming Validator
```typescript
export async function validateNaming(orgId: string, code: string): Promise<{
  issues: { term: string; suggestion: string; line: number }[];
}> {
  const glossary = await Glossary.find({ org: orgId });
  const issues: { term: string; suggestion: string; line: number }[] = [];
  const lines = code.split('\n');

  for (const entry of glossary) {
    for (const alias of [entry.term, ...entry.aliases]) {
      lines.forEach((line, i) => {
        if (line.toLowerCase().includes(alias.toLowerCase()) && entry.preferredCodeName) {
          if (!line.includes(entry.preferredCodeName)) {
            issues.push({ term: alias, suggestion: `Use "${entry.preferredCodeName}" instead of "${alias}"`, line: i + 1 });
          }
        }
      });
    }
  }

  return { issues };
}
```

---

## 6 · Domain Knowledge Checklist

```
Ingestion:
✓ PDF, DOCX, Markdown, plain text support
✓ Semantic chunking by sections (not fixed-size)
✓ Overlap between chunks (10-15%)
✓ Category tagging (policy, api-spec, business-rule, glossary)
✓ Org-level isolation (multi-tenant safe)

Retrieval:
✓ Vector search with org + category filters
✓ Query classification (needs domain context or not)
✓ Top-K retrieval with relevance scores
✓ Source citations in every response

Code Generation:
✓ Domain rules enforced in system prompt
✓ Domain glossary → naming validation
✓ Conflict detection (request vs policy)
✓ Warnings for ambiguous domain areas

Security:
✗ Never send domain docs to public APIs without consent
✓ On-prem / private cloud deployment option
✓ Encryption at rest for stored embeddings
✓ Access control per document category
✓ Audit log of all domain queries
```

---

## Response Format

```
1. Domain context used (sources, sections, relevance)
2. Generated code (domain-compliant, properly named)
3. Domain rule citations (which rule informed which decision)
4. Warnings (conflicts, ambiguities, missing rules)
```

**Never output:** code that violates loaded business rules, generic patterns ignoring domain context, answers without source citations.
**Always output:** domain source references, naming compliance, conflict warnings, confidence level.

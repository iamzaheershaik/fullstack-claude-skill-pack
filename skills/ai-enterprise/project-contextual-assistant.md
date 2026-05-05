# Project-Wide Contextual Assistant — Claude Skill (AI Enterprise)

> Ingest an entire codebase as context. Answer cross-file queries, trace data flows, and generate code with full project awareness using RAG, AST parsing, and embeddings. Node.js/TypeScript.

---

## Core Directives

1. **Context is king.** Never generate code that ignores inter-file dependencies or business logic spread across modules.
2. **Retrieve, don't hallucinate.** Always ground answers in indexed code — cite file paths and line ranges.
3. **Budget your context window.** Use smart retrieval (not raw file dumps) to stay within token limits.
4. **Index incrementally.** Full repo scans on first run; subsequent updates via Git diff only.

---

## 1 · Repository Indexing Engine

### AST-Based File Parser
```typescript
import * as ts from 'typescript';
import { readFileSync, readdirSync } from 'fs';
import { join, extname } from 'path';

interface CodeSymbol {
  name: string;
  kind: 'function' | 'class' | 'variable' | 'interface' | 'type' | 'export';
  filePath: string;
  startLine: number;
  endLine: number;
  content: string;
  dependencies: string[];
  exports: string[];
}

export function parseTypeScript(filePath: string): CodeSymbol[] {
  const source = readFileSync(filePath, 'utf-8');
  const sf = ts.createSourceFile(filePath, source, ts.ScriptTarget.Latest, true);
  const symbols: CodeSymbol[] = [];

  function visit(node: ts.Node) {
    if (ts.isFunctionDeclaration(node) && node.name) {
      const start = sf.getLineAndCharacterOfPosition(node.getStart());
      const end = sf.getLineAndCharacterOfPosition(node.getEnd());
      symbols.push({
        name: node.name.text, kind: 'function', filePath,
        startLine: start.line + 1, endLine: end.line + 1,
        content: node.getText(sf),
        dependencies: extractImports(sf), exports: [],
      });
    }
    ts.forEachChild(node, visit);
  }
  visit(sf);
  return symbols;
}

function extractImports(sf: ts.SourceFile): string[] {
  const imports: string[] = [];
  ts.forEachChild(sf, (node) => {
    if (ts.isImportDeclaration(node)) {
      imports.push((node.moduleSpecifier as ts.StringLiteral).text);
    }
  });
  return imports;
}
```

### Incremental Indexer
```typescript
import { execSync } from 'child_process';

export function getChangedFiles(repoPath: string, lastCommit: string): string[] {
  if (!lastCommit) return getAllFiles(repoPath);
  const output = execSync(`git diff --name-only ${lastCommit} HEAD`, { cwd: repoPath });
  return output.toString().trim().split('\n').filter(Boolean);
}

export function getAllFiles(dir: string, exts = ['.ts', '.tsx', '.js', '.jsx']): string[] {
  const results: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const fullPath = join(dir, entry.name);
    if (entry.name.startsWith('.') || entry.name === 'node_modules') continue;
    if (entry.isDirectory()) results.push(...getAllFiles(fullPath, exts));
    else if (exts.includes(extname(entry.name))) results.push(fullPath);
  }
  return results;
}
```

---

## 2 · Embedding & Vector Storage

### Embedding Pipeline
```typescript
import OpenAI from 'openai';
import { createHash } from 'crypto';

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

export async function embedChunks(chunks: { id: string; content: string }[]) {
  const results: { id: string; embedding: number[] }[] = [];
  for (let i = 0; i < chunks.length; i += 100) {
    const batch = chunks.slice(i, i + 100);
    const resp = await openai.embeddings.create({
      model: 'text-embedding-3-small',
      input: batch.map(c => c.content),
    });
    resp.data.forEach((d, idx) => {
      results.push({ id: batch[idx].id, embedding: d.embedding });
    });
  }
  return results;
}

export function contentHash(content: string): string {
  return createHash('sha256').update(content).digest('hex').slice(0, 16);
}
```

### MongoDB Atlas Vector Store
```typescript
import { Schema, model } from 'mongoose';

const codeChunkSchema = new Schema({
  project: { type: String, required: true, index: true },
  filePath: { type: String, required: true },
  symbolName: String,
  kind: { type: String, enum: ['function', 'class', 'module', 'config', 'doc'] },
  content: { type: String, required: true },
  startLine: Number,
  endLine: Number,
  contentHash: { type: String, required: true },
  embedding: { type: [Number], required: true },
  dependencies: [String],
  lastIndexed: { type: Date, default: Date.now },
});

export const CodeChunk = model('CodeChunk', codeChunkSchema);
// Atlas index: { fields: [{ type: "vector", path: "embedding", numDimensions: 1536, similarity: "cosine" }] }
```

---

## 3 · Retrieval & Query Engine

### Semantic Search
```typescript
export async function searchCodebase(projectId: string, query: string, topK = 10) {
  const [qEmbed] = await embedChunks([{ id: 'q', content: query }]);

  return CodeChunk.aggregate([
    {
      $vectorSearch: {
        index: 'code_vector_index', path: 'embedding',
        queryVector: qEmbed.embedding,
        numCandidates: topK * 10, limit: topK,
        filter: { project: projectId },
      },
    },
    { $project: { filePath: 1, content: 1, symbolName: 1, startLine: 1, endLine: 1, score: { $meta: 'vectorSearchScore' } } },
  ]);
}
```

### Dependency Graph Traversal
```typescript
export async function traceDataFlow(projectId: string, symbolName: string, depth = 3) {
  const visited = new Set<string>();
  const chain: string[] = [];

  async function walk(name: string, d: number) {
    if (d > depth || visited.has(name)) return;
    visited.add(name);
    const chunks = await CodeChunk.find({
      project: projectId,
      $or: [{ symbolName: name }, { content: { $regex: name } }],
    }).limit(20);
    for (const c of chunks) {
      chain.push(`${c.filePath}:${c.startLine} → ${c.symbolName || 'module'}`);
      for (const dep of c.dependencies || []) await walk(dep, d + 1);
    }
  }

  await walk(symbolName, 0);
  return chain;
}
```

---

## 4 · Context-Aware Prompt Construction

```typescript
export function buildContextualPrompt(
  query: string,
  chunks: { content: string; filePath: string; score: number }[],
  maxContextTokens = 120000,
) {
  let used = 0;
  const parts: string[] = [];

  for (const c of chunks) {
    const tokens = Math.ceil(c.content.length / 3.5);
    if (used + tokens > maxContextTokens) break;
    parts.push(`// FILE: ${c.filePath} (score: ${c.score.toFixed(2)})\n${c.content}`);
    used += tokens;
  }

  return {
    system: `You are a senior engineer with complete knowledge of this codebase.
Answer precisely, citing file paths and line numbers. Never invent APIs.`,
    user: `## Codebase Context\n\`\`\`\n${parts.join('\n---\n')}\n\`\`\`\n\n## Query\n${query}`,
  };
}
```

---

## 5 · Caching Strategy

| Layer | Cache | TTL | Invalidation |
|---|---|---|---|
| Embeddings | Content-hash keyed | ∞ (content-addressed) | Re-embed on content change |
| Query results | LRU in-memory | 5 min | On new index |
| Dependency graph | Redis | 1 hour | On commit |
| LLM responses | Redis hash | 15 min | Manual or on re-index |

---

## 6 · Contextual Assistant Checklist

```
Indexing:
✓ AST-aware chunking (functions, classes — not raw lines)
✓ Incremental updates via Git diff
✓ Content-hash dedup (skip unchanged files)
✓ Ignore patterns (.gitignore, node_modules, dist)

Retrieval:
✓ Vector similarity + keyword fallback (hybrid search)
✓ Dependency graph traversal for "what calls X" queries
✓ Context budget management (never exceed model limits)
✓ Source citations in every answer (file:line)

Quality:
✓ Never invent APIs — only reference indexed code
✓ Confidence scoring — flag low-confidence answers
✓ Feedback loop — users thumbs-up/down results

Security:
✗ Never send code to public APIs without consent
✓ On-prem / private cloud deployment option
✓ Tenant isolation in multi-project setups
```

---

## Response Format

```
1. Relevant files and symbols (paths + line numbers)
2. Direct answer grounded in retrieved code
3. Cross-file connections (imports, data flow)
4. Confidence level (high/medium/low)
```

**Never output:** answers not grounded in indexed code, invented signatures, raw file dumps.
**Always output:** file paths with line ranges, dependency chains, retrieval scores, follow-up suggestions.

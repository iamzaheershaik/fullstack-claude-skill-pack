# Collaborative Code Review Facilitator — Claude Skill (AI Enterprise)

> Auto-summarize PRs, enforce style guides, suggest reviewers, link changes to tickets, and generate review comments. Integrates with GitHub/GitLab. Node.js/TypeScript.

---

## Core Directives

1. **Assist, never replace.** AI handles routine commentary — humans decide on logic and architecture.
2. **Context-rich reviews.** Link every PR to tickets, docs, and related past changes.
3. **Consistent standards.** Enforce team style guide automatically — no subjective debates.
4. **Speed up, don't slow down.** Reduce review cycle time, not increase comment noise.

---

## 1 · PR Analysis Engine

### Diff Parser & Summarizer
```typescript
import OpenAI from 'openai';
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

interface PRSummary {
  title: string;
  description: string;
  filesChanged: number;
  linesAdded: number;
  linesRemoved: number;
  riskLevel: 'low' | 'medium' | 'high';
  categories: ('feature' | 'bugfix' | 'refactor' | 'docs' | 'test' | 'config' | 'deps')[];
  breakingChanges: string[];
  keyChanges: { file: string; summary: string }[];
}

export async function summarizePR(diff: string, prTitle: string, prBody: string): Promise<PRSummary> {
  const stats = parseDiffStats(diff);

  const response = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages: [
      {
        role: 'system',
        content: `Summarize this PR for reviewers. Return JSON:
{
  "title": "concise PR title",
  "description": "2-3 sentence summary of what changed and why",
  "riskLevel": "low|medium|high",
  "categories": ["feature"|"bugfix"|"refactor"|"docs"|"test"|"config"|"deps"],
  "breakingChanges": ["list of breaking changes or empty"],
  "keyChanges": [{"file": "path", "summary": "what changed"}]
}
Risk: high if auth/payment/security/schema changes. Low if docs/tests only.`,
      },
      { role: 'user', content: `PR: ${prTitle}\n\n${prBody}\n\nDiff:\n${diff.slice(0, 8000)}` },
    ],
    max_tokens: 1500,
    temperature: 0.2,
    response_format: { type: 'json_object' },
  });

  const parsed = JSON.parse(response.choices[0].message.content || '{}');
  return { ...parsed, filesChanged: stats.files, linesAdded: stats.added, linesRemoved: stats.removed };
}

function parseDiffStats(diff: string) {
  const files = (diff.match(/^diff --git/gm) || []).length;
  const added = (diff.match(/^\+[^+]/gm) || []).length;
  const removed = (diff.match(/^-[^-]/gm) || []).length;
  return { files, added, removed };
}
```

---

## 2 · Review Comment Generator

### Style Guide Enforcer
```typescript
interface StyleRule {
  name: string;
  pattern: RegExp;
  message: string;
  severity: 'error' | 'warning' | 'suggestion';
  autoFixable: boolean;
}

const DEFAULT_RULES: StyleRule[] = [
  { name: 'no-console', pattern: /console\.(log|debug|info)\(/, message: 'Remove console.log — use structured logger', severity: 'warning', autoFixable: true },
  { name: 'no-any', pattern: /:\s*any\b/, message: 'Avoid `any` — use `unknown` with type guards', severity: 'error', autoFixable: false },
  { name: 'max-params', pattern: /\(([^)]*,){4,}[^)]*\)/, message: 'Too many function parameters (>4) — use options object', severity: 'suggestion', autoFixable: false },
  { name: 'no-hardcoded-url', pattern: /['"]https?:\/\/(?!localhost)[^'"]+['"]/, message: 'Hardcoded URL — use environment variable', severity: 'warning', autoFixable: false },
  { name: 'no-magic-number', pattern: /(?<!\w)\b\d{2,}\b(?!\w)(?!.*(?:port|status|code|version|index|length))/, message: 'Magic number — extract to named constant', severity: 'suggestion', autoFixable: false },
  { name: 'error-handling', pattern: /catch\s*\(\s*\w+\s*\)\s*\{\s*\}/, message: 'Empty catch block — handle or log the error', severity: 'error', autoFixable: false },
];

export function enforceStyleGuide(
  diff: string,
  customRules: StyleRule[] = [],
): { file: string; line: number; rule: string; message: string; severity: string }[] {
  const rules = [...DEFAULT_RULES, ...customRules];
  const comments: ReturnType<typeof enforceStyleGuide> = [];

  const files = parseDiffFiles(diff);
  for (const file of files) {
    for (const change of file.additions) {
      for (const rule of rules) {
        if (rule.pattern.test(change.content)) {
          comments.push({ file: file.path, line: change.line, rule: rule.name, message: rule.message, severity: rule.severity });
        }
      }
    }
  }

  return comments;
}

function parseDiffFiles(diff: string): { path: string; additions: { line: number; content: string }[] }[] {
  const files: { path: string; additions: { line: number; content: string }[] }[] = [];
  const fileParts = diff.split(/^diff --git/m).filter(Boolean);

  for (const part of fileParts) {
    const pathMatch = part.match(/b\/(.+)/);
    if (!pathMatch) continue;
    const additions: { line: number; content: string }[] = [];
    let lineNum = 0;
    for (const line of part.split('\n')) {
      const hunkMatch = line.match(/^@@ .+ \+(\d+)/);
      if (hunkMatch) { lineNum = parseInt(hunkMatch[1]); continue; }
      if (line.startsWith('+') && !line.startsWith('+++')) {
        additions.push({ line: lineNum, content: line.slice(1) });
      }
      if (!line.startsWith('-')) lineNum++;
    }
    files.push({ path: pathMatch[1], additions });
  }
  return files;
}
```

### LLM Review Comments
```typescript
export async function generateReviewComments(diff: string, context: {
  prSummary: PRSummary;
  styleGuide?: string;
  recentBugs?: string[];
}): Promise<{ file: string; line: number; comment: string; type: 'issue' | 'suggestion' | 'question' }[]> {
  const response = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages: [
      {
        role: 'system',
        content: `You are a senior code reviewer. Review the PR diff and generate comments.
Focus on: bugs, security, performance, error handling, edge cases, naming.
Skip: formatting, style (those are handled separately).
Return JSON array: [{ "file": string, "line": number, "comment": string, "type": "issue"|"suggestion"|"question" }]
${context.styleGuide ? `\nTeam Style Guide:\n${context.styleGuide}` : ''}
${context.recentBugs?.length ? `\nRecent bugs to watch for:\n${context.recentBugs.join('\n')}` : ''}`,
      },
      { role: 'user', content: diff.slice(0, 12000) },
    ],
    max_tokens: 2000,
    temperature: 0.2,
    response_format: { type: 'json_object' },
  });

  const parsed = JSON.parse(response.choices[0].message.content || '{"comments":[]}');
  return parsed.comments || [];
}
```

---

## 3 · Reviewer Assignment

### Knowledge-Based Matcher
```typescript
interface ReviewerScore {
  username: string;
  score: number;
  reasons: string[];
  availability: 'available' | 'busy' | 'ooo';
}

export async function suggestReviewers(
  changedFiles: string[],
  gitLog: string, // recent git log for file ownership
  teamMembers: { username: string; expertise: string[]; availability: string }[],
): Promise<ReviewerScore[]> {
  // Parse git blame for file ownership
  const ownership = new Map<string, Map<string, number>>();
  const logLines = gitLog.split('\n');
  for (const line of logLines) {
    const match = line.match(/^(\w+)\s+(.+)/);
    if (match) {
      const [, author, file] = match;
      if (!ownership.has(file)) ownership.set(file, new Map());
      ownership.get(file)!.set(author, (ownership.get(file)!.get(author) || 0) + 1);
    }
  }

  // Score reviewers
  const scores: ReviewerScore[] = teamMembers.map(member => {
    let score = 0;
    const reasons: string[] = [];

    for (const file of changedFiles) {
      const fileOwners = ownership.get(file);
      if (fileOwners?.has(member.username)) {
        score += fileOwners.get(member.username)! * 2;
        reasons.push(`Owns ${file} (${fileOwners.get(member.username)} commits)`);
      }

      // Expertise match
      const ext = file.split('.').pop();
      if (member.expertise.some(e => file.includes(e) || ext === e)) {
        score += 5;
        reasons.push(`Expertise in ${ext}`);
      }
    }

    return { username: member.username, score, reasons, availability: member.availability as any };
  });

  return scores.sort((a, b) => b.score - a.score).slice(0, 3);
}
```

---

## 4 · Ticket & Doc Linking

### Issue Tracker Integration
```typescript
export function linkTickets(prTitle: string, prBody: string, diff: string): {
  tickets: { id: string; source: 'jira' | 'github' | 'linear'; url: string }[];
  missingLink: boolean;
} {
  const ticketPatterns = [
    { regex: /([A-Z]+-\d+)/g, source: 'jira' as const, urlTemplate: 'https://jira.company.com/browse/$1' },
    { regex: /#(\d+)/g, source: 'github' as const, urlTemplate: '' },
    { regex: /([A-Z]+-\d+)/g, source: 'linear' as const, urlTemplate: 'https://linear.app/team/issue/$1' },
  ];

  const tickets: { id: string; source: 'jira' | 'github' | 'linear'; url: string }[] = [];
  const combined = `${prTitle} ${prBody}`;

  for (const pattern of ticketPatterns) {
    let match;
    while ((match = pattern.regex.exec(combined))) {
      tickets.push({ id: match[1] || match[0], source: pattern.source, url: pattern.urlTemplate.replace('$1', match[1] || match[0]) });
    }
  }

  return { tickets, missingLink: tickets.length === 0 };
}
```

---

## 5 · GitHub Bot Integration

### Bot Comment Poster
```typescript
export async function postReviewSummary(prNumber: number, data: {
  summary: PRSummary;
  styleIssues: { file: string; line: number; message: string }[];
  aiComments: { file: string; line: number; comment: string; type: string }[];
  suggestedReviewers: ReviewerScore[];
  tickets: { id: string; url: string }[];
}) {
  const { Octokit } = await import('@octokit/rest');
  const octokit = new Octokit({ auth: process.env.GITHUB_TOKEN });
  const [owner, repo] = (process.env.GITHUB_REPOSITORY || '').split('/');

  // Summary comment
  const body = `## 🤖 AI Review Summary

### Overview
${data.summary.description}

**Risk:** ${data.summary.riskLevel} | **Categories:** ${data.summary.categories.join(', ')} | **Files:** ${data.summary.filesChanged} | **+${data.summary.linesAdded} / -${data.summary.linesRemoved}**

${data.summary.breakingChanges.length ? `### ⚠️ Breaking Changes\n${data.summary.breakingChanges.map(c => `- ${c}`).join('\n')}` : ''}

### Key Changes
${data.summary.keyChanges.map(c => `- **${c.file}**: ${c.summary}`).join('\n')}

### Suggested Reviewers
${data.suggestedReviewers.map(r => `- @${r.username} (score: ${r.score}) — ${r.reasons[0]}`).join('\n')}

${data.tickets.length ? `### Linked Tickets\n${data.tickets.map(t => `- [${t.id}](${t.url})`).join('\n')}` : '⚠️ No tickets linked — please add issue reference.'}

---
*${data.styleIssues.length} style issues · ${data.aiComments.length} review comments*`;

  await octokit.issues.createComment({ owner, repo, issue_number: prNumber, body });

  // Inline review comments
  for (const comment of data.aiComments.slice(0, 20)) {
    try {
      await octokit.pulls.createReviewComment({
        owner, repo, pull_number: prNumber,
        body: `🤖 **${comment.type}**: ${comment.comment}`,
        path: comment.file,
        line: comment.line,
        commit_id: '', // set from PR head SHA
      });
    } catch {} // Skip if line doesn't exist in diff
  }
}
```

---

## 6 · Review Priority Scoring

| Change Type | Risk Score | Review Depth |
|---|---|---|
| Auth/security code | +30 | Deep review required |
| Payment/billing | +25 | Deep review + domain expert |
| Database schema migration | +20 | Schema review + rollback plan |
| API contract changes | +15 | Contract review + changelog |
| Business logic | +10 | Logic review |
| Test additions | +2 | Quick scan |
| Docs/comments | +1 | Auto-approve candidate |
| Config/CI changes | +5 | Validate pipeline |

---

## 7 · Code Review Checklist

```
PR Summary:
✓ Auto-generated description (what + why)
✓ Risk level assessment (low/medium/high)
✓ Category tagging (feature/bugfix/refactor)
✓ Breaking change detection
✓ Key changes per file

Review:
✓ Style guide enforcement (automated rules)
✓ LLM-powered logic review (bugs, security, perf)
✓ Inline comments with type (issue/suggestion/question)
✓ Max 20 inline comments (avoid noise)

Workflow:
✓ Reviewer suggestion (based on file ownership + expertise)
✓ Ticket linking (Jira/GitHub/Linear)
✓ Missing ticket warning
✓ Review priority scoring

Integration:
✓ GitHub/GitLab webhook listener
✓ Bot comment on PR (summary + inline)
✓ Request reviewers via API
✗ Never auto-approve — always require human sign-off
```

---

## Response Format

```
1. PR summary (description, risk, categories, breaking changes)
2. Style guide violations (auto-detected)
3. AI review comments (bugs, security, suggestions)
4. Suggested reviewers with reasoning
```

**Never output:** auto-approvals, trivial style nits as blockers, more than 20 inline comments.
**Always output:** PR summary, risk level, ticket links, reviewer suggestions.

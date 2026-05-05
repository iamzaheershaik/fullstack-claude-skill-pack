# AI-Powered Testing & Debugging Suite — Claude Skill (AI Enterprise)

> Auto-generate unit/integration/E2E tests from code or specs, execute in sandbox, capture failures, and iteratively refine. Closes the write→run→debug loop. Node.js/TypeScript.

---

## Core Directives

1. **Test behavior, not implementation.** Generated tests validate what code does, not how it does it.
2. **Close the loop.** Generate → execute → analyze failures → fix → re-run. No manual steps.
3. **Edge cases first.** AI excels at finding boundary conditions humans miss — prioritize them.
4. **Never trust blindly.** AI-generated tests are drafts. Always flag for human review before merging.

---

## 1 · Test Generation Engine

### Function-Level Test Generator
```typescript
import OpenAI from 'openai';
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

interface GeneratedTest {
  testCode: string;
  framework: 'vitest' | 'jest' | 'pytest';
  coverageTarget: string[];
  edgeCases: string[];
}

export async function generateTests(
  sourceCode: string,
  filePath: string,
  options: { framework?: string; style?: 'unit' | 'integration' | 'e2e' } = {},
): Promise<GeneratedTest> {
  const framework = options.framework || 'vitest';
  const style = options.style || 'unit';

  const response = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages: [
      {
        role: 'system',
        content: `You are a senior QA engineer. Generate ${style} tests using ${framework}.
Rules:
- Test behavior, not implementation details
- Use descriptive test names: "should [expected behavior] when [condition]"
- One assertion concept per test
- Include edge cases: empty inputs, nulls, boundaries, error paths
- Use factory functions for test data — no hardcoded fixtures
- Mock at boundaries only (DB, external APIs)
- Return ONLY valid test code, no explanations`,
      },
      {
        role: 'user',
        content: `Generate ${style} tests for:\n\nFile: ${filePath}\n\`\`\`\n${sourceCode}\n\`\`\``,
      },
    ],
    max_tokens: 3000,
    temperature: 0.3,
  });

  const testCode = extractCodeBlock(response.choices[0].message.content || '');
  const edgeCases = extractEdgeCases(testCode);

  return { testCode, framework: framework as any, coverageTarget: [filePath], edgeCases };
}

function extractCodeBlock(content: string): string {
  const match = content.match(/```(?:typescript|javascript|ts|js)?\n([\s\S]*?)```/);
  return match ? match[1] : content;
}

function extractEdgeCases(testCode: string): string[] {
  const cases: string[] = [];
  const regex = /(?:it|test)\(['"](.+?)['"]/g;
  let m;
  while ((m = regex.exec(testCode))) cases.push(m[1]);
  return cases;
}
```

### Integration Test Generator
```typescript
export async function generateAPITests(
  routeCode: string,
  schemaCode: string,
  basePath: string,
): Promise<string> {
  const response = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages: [
      {
        role: 'system',
        content: `Generate integration tests using Supertest + Vitest for Express routes.
Rules:
- Test full request → response cycle
- Include: 200 success, 400 validation, 401 auth, 404 not found, 500 error
- Use test database (in-memory MongoDB via mongodb-memory-server)
- Setup: seed data before each test, cleanup after
- Test pagination, filtering, sorting if applicable
- Validate response shape (not just status code)
Return only valid test code.`,
      },
      {
        role: 'user',
        content: `Route code:\n\`\`\`\n${routeCode}\n\`\`\`\n\nSchema:\n\`\`\`\n${schemaCode}\n\`\`\`\n\nBase path: ${basePath}`,
      },
    ],
    max_tokens: 3000,
    temperature: 0.3,
  });

  return extractCodeBlock(response.choices[0].message.content || '');
}
```

### E2E Test Generator
```typescript
export async function generateE2ETests(
  pageDescription: string,
  userFlows: string[],
): Promise<string> {
  const response = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages: [
      {
        role: 'system',
        content: `Generate Playwright E2E tests.
Rules:
- Use Page Object Model pattern
- Test critical user flows end-to-end
- Include: happy path, error states, edge cases
- Use data-testid selectors (not CSS classes)
- Wait for network idle before assertions
- Screenshot on failure
Return only valid test code.`,
      },
      {
        role: 'user',
        content: `Page: ${pageDescription}\n\nFlows to test:\n${userFlows.map((f, i) => `${i + 1}. ${f}`).join('\n')}`,
      },
    ],
    max_tokens: 3000,
    temperature: 0.3,
  });

  return extractCodeBlock(response.choices[0].message.content || '');
}
```

---

## 2 · Sandbox Execution Engine

### Test Runner
```typescript
import { execSync, ExecSyncOptionsWithStringEncoding } from 'child_process';
import { writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';

interface TestResult {
  passed: boolean;
  totalTests: number;
  passedTests: number;
  failedTests: number;
  failures: { testName: string; error: string; file: string; line?: number }[];
  coverage?: { lines: number; branches: number; functions: number };
  duration: number;
}

export function runTests(testCode: string, projectDir: string): TestResult {
  const testFile = join(projectDir, '__generated__', `test_${Date.now()}.test.ts`);
  mkdirSync(join(projectDir, '__generated__'), { recursive: true });
  writeFileSync(testFile, testCode);

  const startTime = Date.now();
  try {
    const output = execSync(
      `npx vitest run ${testFile} --reporter=json --coverage.enabled`,
      { cwd: projectDir, encoding: 'utf-8', timeout: 60000 },
    );

    const results = JSON.parse(output);
    return parseVitestResults(results, Date.now() - startTime);
  } catch (e: any) {
    return parseFailedRun(e.stdout || e.message, Date.now() - startTime);
  }
}

function parseVitestResults(json: any, duration: number): TestResult {
  const tests = json.testResults?.[0]?.assertionResults || [];
  const failures = tests
    .filter((t: any) => t.status === 'failed')
    .map((t: any) => ({ testName: t.fullName, error: t.failureMessages?.join('\n') || '', file: '' }));

  return {
    passed: failures.length === 0,
    totalTests: tests.length,
    passedTests: tests.filter((t: any) => t.status === 'passed').length,
    failedTests: failures.length,
    failures,
    duration,
  };
}

function parseFailedRun(output: string, duration: number): TestResult {
  return { passed: false, totalTests: 0, passedTests: 0, failedTests: 1, failures: [{ testName: 'runner', error: output, file: '' }], duration };
}
```

---

## 3 · Iterative Debug Loop

### Auto-Fix Pipeline
```typescript
export async function iterativeTestFix(
  sourceCode: string,
  testCode: string,
  projectDir: string,
  maxIterations = 3,
): Promise<{ finalTestCode: string; finalResult: TestResult; iterations: number }> {
  let currentTest = testCode;

  for (let i = 0; i < maxIterations; i++) {
    const result = runTests(currentTest, projectDir);

    if (result.passed) {
      return { finalTestCode: currentTest, finalResult: result, iterations: i + 1 };
    }

    // Ask LLM to fix the failing tests
    const response = await openai.chat.completions.create({
      model: 'gpt-4o',
      messages: [
        {
          role: 'system',
          content: `Fix the failing tests. Analyze the error messages and the source code.
Only modify the test code — do not change the source. Return the complete fixed test file.`,
        },
        {
          role: 'user',
          content: `## Source\n\`\`\`\n${sourceCode}\n\`\`\`\n\n## Tests\n\`\`\`\n${currentTest}\n\`\`\`\n\n## Failures\n${result.failures.map(f => `${f.testName}: ${f.error}`).join('\n\n')}`,
        },
      ],
      max_tokens: 3000,
      temperature: 0.2,
    });

    currentTest = extractCodeBlock(response.choices[0].message.content || currentTest);
  }

  const finalResult = runTests(currentTest, projectDir);
  return { finalTestCode: currentTest, finalResult, iterations: maxIterations };
}
```

---

## 4 · Coverage Analysis

### Coverage Gap Finder
```typescript
export async function findCoverageGaps(
  coverageReport: { file: string; lines: { covered: number[]; uncovered: number[] } }[],
  sourceFiles: { path: string; content: string }[],
): Promise<{ file: string; uncoveredFunctions: string[]; suggestion: string }[]> {
  const gaps: { file: string; uncoveredFunctions: string[]; suggestion: string }[] = [];

  for (const report of coverageReport) {
    if (report.lines.uncovered.length === 0) continue;

    const source = sourceFiles.find(f => f.path === report.file);
    if (!source) continue;

    const lines = source.content.split('\n');
    const uncoveredCode = report.lines.uncovered.map(l => lines[l - 1]).filter(Boolean).join('\n');

    const fnNames = (uncoveredCode.match(/(?:function|const|let)\s+(\w+)/g) || [])
      .map(m => m.replace(/(?:function|const|let)\s+/, ''));

    gaps.push({
      file: report.file,
      uncoveredFunctions: fnNames,
      suggestion: `Generate tests for: ${fnNames.join(', ')} in ${report.file}`,
    });
  }

  return gaps;
}
```

---

## 5 · Test Strategy Matrix

| Code Type | Test Style | Framework | Priority |
|---|---|---|---|
| Pure utility functions | Unit | Vitest | High |
| Express route handlers | Integration | Supertest | High |
| React components | Component | Testing Library | Medium |
| Auth flows | Integration + E2E | Supertest + Playwright | Critical |
| Payment processing | Integration | Supertest + mocks | Critical |
| UI user flows | E2E | Playwright | Medium |
| Data transformations | Unit | Vitest | High |
| Error handlers | Unit + Integration | Vitest + Supertest | High |

---

## 6 · Testing Suite Checklist

```
Generation:
✓ Unit tests from function signatures + JSDoc
✓ Integration tests from route definitions + schemas
✓ E2E tests from user flow descriptions
✓ Edge case discovery (nulls, boundaries, errors)
✓ Factory functions for test data (no hardcoded fixtures)

Execution:
✓ Sandboxed runner (containerized or temp dir)
✓ Timeout per test (30s unit, 60s integration, 120s E2E)
✓ Coverage collection (lines, branches, functions)
✓ JSON-structured results for programmatic use

Iteration:
✓ Auto-fix failing tests (max 3 iterations)
✓ Coverage gap analysis → generate missing tests
✓ Mutation testing to validate test quality
✗ Never auto-merge AI-generated tests
✓ Human review flag on every generated file

Reporting:
✓ Coverage trend over time
✓ Test-to-code ratio tracking
✓ Flaky test detection (intermittent failures)
```

---

## Response Format

```
1. Generated test file (complete, runnable)
2. Execution results (pass/fail, coverage %)
3. Edge cases covered (boundary list)
4. Coverage gaps identified (functions needing tests)
```

**Never output:** tests that mock the unit under test, implementation-coupled tests, tests without assertions.
**Always output:** descriptive test names, edge cases, factory functions, coverage report.

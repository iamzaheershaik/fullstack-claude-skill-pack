# Test Writer — Claude Skill

> Write comprehensive, maintainable tests. Vitest, Supertest, Playwright, React Testing Library. Test behavior, not implementation.

---

## Core Directives

1. **Test behavior, not implementation.** Tests should survive refactors.
2. **One concept per test.** Multiple expects OK if testing one logical thing.
3. **Tests are documentation.** Names should describe expected behavior for humans.
4. **Fast feedback loop.** Unit tests < 50ms each. Integration < 500ms. E2E < 10s.

---

## 1 · Vitest Setup & Configuration

### Config
```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';
import path from 'path';

export default defineConfig({
  test: {
    globals: true,                    // describe, it, expect globally
    environment: 'node',              // or 'jsdom' for React
    include: ['src/**/*.test.ts', 'src/**/*.spec.ts'],
    exclude: ['**/e2e/**', '**/node_modules/**'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html', 'lcov'],
      include: ['src/**/*.ts'],
      exclude: ['src/**/*.test.ts', 'src/**/*.d.ts', 'src/types/**'],
      thresholds: {
        branches: 80,
        functions: 80,
        lines: 80,
        statements: 80,
      },
    },
    setupFiles: ['./src/test/setup.ts'],
  },
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
});
```

### Setup File
```typescript
// src/test/setup.ts
import { beforeAll, afterAll, afterEach } from 'vitest';
import { connectTestDB, disconnectTestDB, clearTestDB } from './helpers/db';

beforeAll(async () => {
  await connectTestDB();
});

afterEach(async () => {
  await clearTestDB();
});

afterAll(async () => {
  await disconnectTestDB();
});
```

### Package Scripts
```json
{
  "scripts": {
    "test": "vitest",
    "test:unit": "vitest run --exclude='**/integration/**'",
    "test:integration": "vitest run --include='**/integration/**'",
    "test:coverage": "vitest run --coverage",
    "test:watch": "vitest --watch",
    "test:e2e": "playwright test"
  }
}
```

---

## 2 · Unit Test Patterns

### Service Layer Tests
```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { PostService } from '../post.service';
import { PostRepository } from '../post.repository';
import { createMockPost, createMockUser } from '@/test/factories';

// Mock the repository
vi.mock('../post.repository');

describe('PostService', () => {
  let service: PostService;
  let repo: ReturnType<typeof vi.mocked<PostRepository>>;

  beforeEach(() => {
    repo = vi.mocked(new PostRepository());
    service = new PostService(repo);
  });

  describe('create', () => {
    it('creates a post with valid input', async () => {
      const input = { title: 'Test Post', content: 'Content here' };
      const user = createMockUser();
      const expected = createMockPost({ ...input, author: user.id });

      repo.create.mockResolvedValue(expected);

      const result = await service.create(input, user.id);

      expect(result).toEqual(expected);
      expect(repo.create).toHaveBeenCalledWith({ ...input, author: user.id });
    });

    it('throws when title exceeds max length', async () => {
      const input = { title: 'a'.repeat(201), content: 'Content' };

      await expect(service.create(input, 'userId'))
        .rejects.toThrow('Title must be 200 characters or less');
    });
  });

  describe('findById', () => {
    it('returns the post when found', async () => {
      const post = createMockPost();
      repo.findById.mockResolvedValue(post);

      const result = await service.findById(post.id);
      expect(result).toEqual(post);
    });

    it('throws NotFoundError when post does not exist', async () => {
      repo.findById.mockResolvedValue(null);

      await expect(service.findById('nonexistent'))
        .rejects.toThrow('Post not found');
    });
  });
});
```

### Validator Tests
```typescript
describe('CreatePostDto', () => {
  it('accepts valid input', () => {
    const result = CreatePostDto.safeParse({
      title: 'Valid Title', content: 'Valid content', tags: ['tag1'],
    });
    expect(result.success).toBe(true);
  });

  it('rejects empty title', () => {
    const result = CreatePostDto.safeParse({ title: '', content: 'Content' });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0].path).toEqual(['title']);
  });

  it('trims and lowercases email', () => {
    const result = CreateUserDto.parse({ email: '  TEST@Email.COM  ', password: 'password123', name: 'Test' });
    expect(result.email).toBe('test@email.com');
  });
});
```

### Utility Function Tests
```typescript
describe('slugify', () => {
  it.each([
    ['Hello World', 'hello-world'],
    ['  Spaces  Around  ', 'spaces-around'],
    ['Special $#@ Characters', 'special-characters'],
    ['Already-slugified', 'already-slugified'],
    ['UPPERCASE', 'uppercase'],
  ])('converts "%s" to "%s"', (input, expected) => {
    expect(slugify(input)).toBe(expected);
  });
});
```

---

## 3 · Integration Tests (Supertest)

### API Endpoint Tests
```typescript
import request from 'supertest';
import { app } from '@/app';
import { createMockUser, createMockPost } from '@/test/factories';
import { User } from '@/modules/user/user.model';
import { Post } from '@/modules/post/post.model';
import { tokenService } from '@/modules/auth/token.service';

describe('POST /api/v1/posts', () => {
  let authToken: string;
  let userId: string;

  beforeEach(async () => {
    const user = await User.create(createMockUser());
    userId = user.id;
    authToken = tokenService.generateAccessToken(user.id, user.role);
  });

  it('creates a post and returns 201', async () => {
    const res = await request(app)
      .post('/api/v1/posts')
      .set('Authorization', `Bearer ${authToken}`)
      .send({ title: 'New Post', content: 'Post content' });

    expect(res.status).toBe(201);
    expect(res.body.data).toMatchObject({
      title: 'New Post',
      content: 'Post content',
      author: userId,
    });
    expect(res.body.data.id).toBeDefined();

    // Verify persisted
    const saved = await Post.findById(res.body.data.id);
    expect(saved).not.toBeNull();
  });

  it('returns 400 for invalid input', async () => {
    const res = await request(app)
      .post('/api/v1/posts')
      .set('Authorization', `Bearer ${authToken}`)
      .send({ title: '', content: '' });

    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
    expect(res.body.error.details).toContainEqual(
      expect.objectContaining({ field: 'title' }),
    );
  });

  it('returns 401 without auth token', async () => {
    const res = await request(app)
      .post('/api/v1/posts')
      .send({ title: 'Test', content: 'Content' });

    expect(res.status).toBe(401);
  });
});

describe('GET /api/v1/posts', () => {
  it('returns paginated posts', async () => {
    // Seed 25 posts
    const user = await User.create(createMockUser());
    await Post.insertMany(Array.from({ length: 25 }, (_, i) =>
      createMockPost({ title: `Post ${i}`, author: user.id }),
    ));

    const res = await request(app)
      .get('/api/v1/posts?page=2&limit=10');

    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(10);
    expect(res.body.meta).toMatchObject({ page: 2, limit: 10, total: 25 });
  });

  it('filters by status', async () => {
    const user = await User.create(createMockUser());
    await Post.create(createMockPost({ status: 'published', author: user.id }));
    await Post.create(createMockPost({ status: 'draft', author: user.id }));

    const res = await request(app).get('/api/v1/posts?status=published');

    expect(res.body.data).toHaveLength(1);
    expect(res.body.data[0].status).toBe('published');
  });
});
```

---

## 4 · E2E Tests (Playwright)

### Setup
```typescript
// playwright.config.ts
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [['html', { open: 'never' }]],
  use: {
    baseURL: 'http://localhost:5173',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  webServer: {
    command: 'npm run dev',
    port: 5173,
    reuseExistingServer: !process.env.CI,
  },
});
```

### Auth Flow Test
```typescript
import { test, expect } from '@playwright/test';

test.describe('Authentication', () => {
  test('user can register, login, and access dashboard', async ({ page }) => {
    // Register
    await page.goto('/register');
    await page.fill('#email', 'test@example.com');
    await page.fill('#password', 'SecurePass123');
    await page.fill('#name', 'Test User');
    await page.click('button[type="submit"]');

    await expect(page).toHaveURL('/dashboard');
    await expect(page.locator('h1')).toContainText('Dashboard');

    // Logout
    await page.click('[data-testid="user-menu"]');
    await page.click('[data-testid="logout-btn"]');
    await expect(page).toHaveURL('/login');

    // Login
    await page.fill('#email', 'test@example.com');
    await page.fill('#password', 'SecurePass123');
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL('/dashboard');
  });

  test('shows error for invalid credentials', async ({ page }) => {
    await page.goto('/login');
    await page.fill('#email', 'wrong@example.com');
    await page.fill('#password', 'wrongpassword');
    await page.click('button[type="submit"]');

    await expect(page.locator('[role="alert"]')).toContainText('Invalid email or password');
    await expect(page).toHaveURL('/login');
  });
});
```

### Page Object Pattern
```typescript
// e2e/pages/LoginPage.ts
export class LoginPage {
  constructor(private page: Page) {}

  async goto() { await this.page.goto('/login'); }
  async login(email: string, password: string) {
    await this.page.fill('#email', email);
    await this.page.fill('#password', password);
    await this.page.click('button[type="submit"]');
  }
  async expectError(message: string) {
    await expect(this.page.locator('[role="alert"]')).toContainText(message);
  }
}

// Usage in test
test('login flow', async ({ page }) => {
  const loginPage = new LoginPage(page);
  await loginPage.goto();
  await loginPage.login('test@example.com', 'password123');
});
```

---

## 5 · React Component Tests

```tsx
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { PostForm } from './PostForm';

describe('PostForm', () => {
  const mockSubmit = vi.fn();

  it('submits valid form data', async () => {
    const user = userEvent.setup();
    render(<PostForm onSubmit={mockSubmit} />);

    await user.type(screen.getByLabelText(/title/i), 'My Post');
    await user.type(screen.getByLabelText(/content/i), 'Post content here');
    await user.click(screen.getByRole('button', { name: /save/i }));

    await waitFor(() => {
      expect(mockSubmit).toHaveBeenCalledWith({
        title: 'My Post', content: 'Post content here', tags: [],
      });
    });
  });

  it('shows validation errors for empty fields', async () => {
    const user = userEvent.setup();
    render(<PostForm onSubmit={mockSubmit} />);

    await user.click(screen.getByRole('button', { name: /save/i }));

    expect(await screen.findByText(/required/i)).toBeInTheDocument();
    expect(mockSubmit).not.toHaveBeenCalled();
  });

  it('disables submit button while loading', async () => {
    mockSubmit.mockImplementation(() => new Promise(() => {})); // never resolves
    const user = userEvent.setup();
    render(<PostForm onSubmit={mockSubmit} />);

    await user.type(screen.getByLabelText(/title/i), 'Test');
    await user.type(screen.getByLabelText(/content/i), 'Content');
    await user.click(screen.getByRole('button', { name: /save/i }));

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /saving/i })).toBeDisabled();
    });
  });
});
```

---

## 6 · Test Organization Rules

### Naming
```
✓ "creates a post with valid input"
✓ "returns 404 when post does not exist"
✓ "shows validation error for empty email"
✗ "test post creation"
✗ "should work"
✗ "test 1"
```

### Structure
```
✓ Group by feature/module, not by type
✓ describe blocks mirror component/function names
✓ Arrange → Act → Assert pattern
✓ Setup shared state in beforeEach, not in tests
✓ Each test is independent (no test ordering dependencies)
✗ Don't share state between tests
✗ Don't test private methods (test through public API)
```

### Coverage Strategy
```
✓ 80%+ on critical paths (auth, payments, data mutations)
✓ 100% on validators and DTOs
✓ Skip coverage for: generated code, types, config files
✓ Coverage is a metric, not a goal — high coverage ≠ good tests
```

---

## 7 · CI Integration

```yaml
test:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-node@v4
      with: { node-version: 20, cache: 'npm' }
    - run: npm ci
    - run: npm run test:unit -- --coverage --reporter=junit --outputFile=results.xml
    - run: npm run test:integration
    - uses: actions/upload-artifact@v4
      if: always()
      with:
        name: test-results
        path: |
          results.xml
          coverage/

# Playwright in CI
e2e:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-node@v4
      with: { node-version: 20, cache: 'npm' }
    - run: npm ci
    - run: npx playwright install --with-deps
    - run: npm run test:e2e
    - uses: actions/upload-artifact@v4
      if: failure()
      with:
        name: playwright-report
        path: playwright-report/
```

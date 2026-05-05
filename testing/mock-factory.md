# Mock Factory — Claude Skill

> Build test data factories and mock strategies. Faker.js factories, database seeding, API mocking with MSW, external service mocks.

---

## Core Directives

1. **Factories over fixtures.** Generate test data, don't copy-paste it.
2. **Override only what matters.** Defaults for everything, explicit for what the test cares about.
3. **Mock at boundaries.** DB, external APIs, time — never mock the unit under test.
4. **Realistic data.** Use faker for plausible values — catches edge cases raw strings miss.

---

## 1 · Factory Pattern

### Base Factory
```typescript
// test/factories/user.factory.ts
import { faker } from '@faker-js/faker';
import { Types } from 'mongoose';

interface UserAttrs {
  _id?: string;
  email?: string;
  password?: string;
  name?: string;
  role?: 'user' | 'admin' | 'moderator';
  isVerified?: boolean;
  createdAt?: Date;
}

export function createMockUser(overrides: Partial<UserAttrs> = {}): UserAttrs {
  return {
    _id: new Types.ObjectId().toString(),
    email: faker.internet.email().toLowerCase(),
    password: 'hashed_password_placeholder',
    name: faker.person.fullName(),
    role: 'user',
    isVerified: true,
    createdAt: faker.date.recent({ days: 30 }),
    ...overrides,
  };
}

// Create in DB
export async function createUser(overrides: Partial<UserAttrs> = {}) {
  const attrs = createMockUser(overrides);
  return User.create(attrs);
}

// Create with auth token (for integration tests)
export async function createAuthenticatedUser(overrides: Partial<UserAttrs> = {}) {
  const user = await createUser(overrides);
  const token = tokenService.generateAccessToken(user.id, user.role);
  return { user, token };
}
```

### Post Factory
```typescript
export function createMockPost(overrides: Partial<PostAttrs> = {}): PostAttrs {
  return {
    _id: new Types.ObjectId().toString(),
    title: faker.lorem.sentence({ min: 3, max: 8 }),
    slug: faker.helpers.slugify(faker.lorem.words(3)).toLowerCase(),
    content: faker.lorem.paragraphs(3),
    status: 'published',
    author: new Types.ObjectId().toString(),
    tags: faker.helpers.arrayElements(['javascript', 'react', 'node', 'mongodb', 'typescript'], { min: 1, max: 3 }),
    metadata: {
      readTime: faker.number.int({ min: 2, max: 15 }),
      wordCount: faker.number.int({ min: 100, max: 3000 }),
      views: faker.number.int({ min: 0, max: 10000 }),
    },
    createdAt: faker.date.recent({ days: 90 }),
    ...overrides,
  };
}
```

### Factory Barrel Export
```typescript
// test/factories/index.ts
export { createMockUser, createUser, createAuthenticatedUser } from './user.factory';
export { createMockPost, createPost } from './post.factory';
export { createMockComment } from './comment.factory';
```

---

## 2 · Factory Composition

### Related Entities
```typescript
// Create a post with its author
export async function createPostWithAuthor(overrides: Partial<PostAttrs> = {}) {
  const author = await createUser();
  const post = await createPost({ author: author.id, ...overrides });
  return { post, author };
}

// Create multiple related entities
export async function createPostWithComments(commentCount = 3) {
  const { post, author } = await createPostWithAuthor();
  const commenters = await Promise.all(
    Array.from({ length: commentCount }, () => createUser()),
  );
  const comments = await Promise.all(
    commenters.map((user) =>
      Comment.create({
        post: post.id,
        author: user.id,
        content: faker.lorem.sentence(),
      }),
    ),
  );
  return { post, author, commenters, comments };
}
```

### Batch Factory
```typescript
export async function createManyPosts(count: number, overrides: Partial<PostAttrs> = {}) {
  const author = await createUser();
  return Post.insertMany(
    Array.from({ length: count }, () => createMockPost({ author: author.id, ...overrides })),
  );
}
```

### Sequence Factory
```typescript
let userCounter = 0;

export function createSequentialUser(overrides: Partial<UserAttrs> = {}): UserAttrs {
  userCounter++;
  return createMockUser({
    email: `user${userCounter}@test.com`,
    name: `User ${userCounter}`,
    ...overrides,
  });
}

// Reset in beforeEach
beforeEach(() => { userCounter = 0; });
```

---

## 3 · Database Test Helpers

### MongoDB Test Database
```typescript
// test/helpers/db.ts
import mongoose from 'mongoose';
import { MongoMemoryServer } from 'mongodb-memory-server';

let mongoServer: MongoMemoryServer;

export async function connectTestDB() {
  mongoServer = await MongoMemoryServer.create();
  await mongoose.connect(mongoServer.getUri());
}

export async function clearTestDB() {
  const collections = mongoose.connection.collections;
  for (const key in collections) {
    await collections[key].deleteMany({});
  }
}

export async function disconnectTestDB() {
  await mongoose.disconnect();
  await mongoServer.stop();
}
```

### Seed Data (For E2E / Staging)
```typescript
// scripts/seed.ts
import { createUser, createPost } from '../test/factories';

export async function seedDatabase() {
  // Admin user
  const admin = await createUser({
    email: 'admin@example.com',
    password: await argon2.hash('admin123'),
    role: 'admin',
  });

  // Regular users
  const users = await Promise.all(
    Array.from({ length: 10 }, () => createUser()),
  );

  // Posts
  for (const user of users) {
    const count = faker.number.int({ min: 2, max: 8 });
    await Promise.all(
      Array.from({ length: count }, () =>
        createPost({ author: user.id, status: faker.helpers.arrayElement(['draft', 'published']) }),
      ),
    );
  }

  console.log(`Seeded: 1 admin, 10 users, ~50 posts`);
}
```

---

## 4 · API Mocking (MSW — Client Side)

### Setup
```typescript
// test/mocks/handlers.ts
import { http, HttpResponse } from 'msw';

export const handlers = [
  // GET posts
  http.get('/api/v1/posts', ({ request }) => {
    const url = new URL(request.url);
    const page = Number(url.searchParams.get('page') || 1);

    return HttpResponse.json({
      data: Array.from({ length: 10 }, () => createMockPost()),
      meta: { page, limit: 10, total: 50 },
    });
  }),

  // GET single post
  http.get('/api/v1/posts/:id', ({ params }) => {
    return HttpResponse.json({
      data: createMockPost({ _id: params.id as string }),
    });
  }),

  // POST create
  http.post('/api/v1/posts', async ({ request }) => {
    const body = await request.json();
    return HttpResponse.json(
      { data: createMockPost(body as any) },
      { status: 201 },
    );
  }),

  // Error simulation
  http.delete('/api/v1/posts/:id', () => {
    return HttpResponse.json(
      { error: { code: 'FORBIDDEN', message: 'Not authorized' } },
      { status: 403 },
    );
  }),
];
```

### MSW Server Setup
```typescript
// test/mocks/server.ts
import { setupServer } from 'msw/node';
import { handlers } from './handlers';

export const server = setupServer(...handlers);

// test/setup.ts
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

### Override Handlers Per Test
```typescript
it('shows error when API fails', async () => {
  server.use(
    http.get('/api/v1/posts', () => {
      return HttpResponse.json(
        { error: { code: 'INTERNAL_ERROR', message: 'Server error' } },
        { status: 500 },
      );
    }),
  );

  render(<PostList />);
  expect(await screen.findByText(/server error/i)).toBeInTheDocument();
});
```

---

## 5 · Server-Side Mocking (nock)

```typescript
import nock from 'nock';

describe('PaymentService', () => {
  afterEach(() => nock.cleanAll());

  it('processes payment via Stripe', async () => {
    nock('https://api.stripe.com')
      .post('/v1/charges')
      .reply(200, {
        id: 'ch_test123',
        status: 'succeeded',
        amount: 2000,
      });

    const result = await paymentService.charge({ amount: 2000, currency: 'usd' });
    expect(result.status).toBe('succeeded');
  });

  it('handles Stripe API failure', async () => {
    nock('https://api.stripe.com')
      .post('/v1/charges')
      .reply(402, { error: { message: 'Card declined' } });

    await expect(paymentService.charge({ amount: 2000 }))
      .rejects.toThrow('Card declined');
  });
});
```

---

## 6 · Time & Date Mocking

```typescript
import { vi, afterEach } from 'vitest';

describe('token expiry', () => {
  afterEach(() => vi.useRealTimers());

  it('rejects expired tokens', () => {
    const now = new Date('2024-01-15T12:00:00Z');
    vi.setSystemTime(now);

    const token = tokenService.generateAccessToken('user1', 'user');

    // Advance 16 minutes (token expires at 15min)
    vi.advanceTimersByTime(16 * 60 * 1000);

    expect(() => tokenService.verifyAccessToken(token)).toThrow();
  });

  it('accepts valid tokens within TTL', () => {
    vi.setSystemTime(new Date('2024-01-15T12:00:00Z'));
    const token = tokenService.generateAccessToken('user1', 'user');

    vi.advanceTimersByTime(14 * 60 * 1000); // 14 minutes

    expect(() => tokenService.verifyAccessToken(token)).not.toThrow();
  });
});
```

---

## 7 · External Service Mocks

### Email (Resend / Nodemailer)
```typescript
export const mockEmailService = {
  send: vi.fn().mockResolvedValue({ id: 'mock-email-id', status: 'sent' }),
  sendTemplate: vi.fn().mockResolvedValue({ id: 'mock-email-id' }),
};

// In test setup
vi.mock('@/lib/email', () => ({ emailService: mockEmailService }));
```

### File Upload (S3)
```typescript
export const mockS3 = {
  upload: vi.fn().mockResolvedValue({
    Location: 'https://bucket.s3.amazonaws.com/test-file.jpg',
    Key: 'test-file.jpg',
    ETag: '"abc123"',
  }),
  delete: vi.fn().mockResolvedValue({}),
  getSignedUrl: vi.fn().mockReturnValue('https://signed-url.example.com'),
};

vi.mock('@/lib/storage', () => ({ s3: mockS3 }));
```

---

## 8 · Mock Rules

```
✓ Mock at boundaries (DB, APIs, filesystem, time)
✓ Use factories for data, mocks for services
✓ Reset mocks between tests (afterEach → vi.clearAllMocks())
✓ Verify mock calls when the test is about side effects
✓ Use mockResolvedValueOnce for sequential calls
✗ Never mock the module being tested
✗ Never leave mocks that leak between tests
✗ Don't mock what you can test with an in-memory DB
✗ Don't over-mock — if you're mocking 5+ things, the code needs refactoring
```

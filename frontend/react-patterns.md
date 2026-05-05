# React Patterns — Claude Skill

> Build maintainable, performant React applications. Component architecture, hooks, state management, forms, routing. TypeScript-first.

---

## Core Directives

1. **Composition over inheritance.** Build small, focused components that compose together.
2. **Colocation.** Keep related code together — styles, tests, types next to the component.
3. **Derive, don't duplicate.** Compute values from state instead of syncing multiple states.
4. **Server by default.** Use server components unless you need interactivity (Next.js App Router).

---

## 1 · Component Architecture

### File Structure (Feature-Sliced)
```
src/
├── app/                  # Routes / pages
│   ├── layout.tsx
│   ├── page.tsx
│   └── (auth)/
│       ├── login/page.tsx
│       └── register/page.tsx
├── components/           # Shared UI components
│   ├── ui/               # Primitives (Button, Input, Card)
│   └── layout/           # Layout components (Header, Sidebar)
├── features/             # Feature modules
│   └── posts/
│       ├── components/   # Feature-specific components
│       ├── hooks/        # Feature-specific hooks
│       ├── api.ts        # API calls
│       ├── types.ts
│       └── index.ts      # Public API
├── hooks/                # Shared hooks
├── lib/                  # Utilities, clients
├── stores/               # State management
└── types/                # Global types
```

### Component Patterns

**Container / Presentational Split**
```tsx
// PostList.tsx — container (data + logic)
export function PostList() {
  const { data, isLoading } = usePosts();
  if (isLoading) return <PostListSkeleton />;
  return <PostGrid posts={data} />;
}

// PostGrid.tsx — presentational (pure rendering)
interface PostGridProps { posts: Post[] }
export function PostGrid({ posts }: PostGridProps) {
  return (
    <div className="grid">
      {posts.map(post => <PostCard key={post.id} post={post} />)}
    </div>
  );
}
```

**Compound Components**
```tsx
// Usage: <Select><Select.Trigger /><Select.Content>...</Select.Content></Select>
const SelectContext = createContext<SelectContextType | null>(null);

function Select({ children, value, onChange }: SelectProps) {
  const [open, setOpen] = useState(false);
  return (
    <SelectContext.Provider value={{ value, onChange, open, setOpen }}>
      <div className="select-root">{children}</div>
    </SelectContext.Provider>
  );
}

Select.Trigger = function Trigger() {
  const ctx = useContext(SelectContext)!;
  return <button onClick={() => ctx.setOpen(!ctx.open)}>{ctx.value}</button>;
};

Select.Content = function Content({ children }: { children: ReactNode }) {
  const ctx = useContext(SelectContext)!;
  if (!ctx.open) return null;
  return <div className="select-content">{children}</div>;
};
```

**Polymorphic Component**
```tsx
type ButtonProps<T extends ElementType = 'button'> = {
  as?: T;
  variant?: 'primary' | 'secondary' | 'ghost';
} & ComponentPropsWithoutRef<T>;

function Button<T extends ElementType = 'button'>({
  as, variant = 'primary', className, ...props
}: ButtonProps<T>) {
  const Component = as || 'button';
  return <Component className={`btn btn-${variant} ${className}`} {...props} />;
}

// Usage: <Button as="a" href="/about">Link styled as button</Button>
```

---

## 2 · Custom Hooks

### Data Fetching Hook
```tsx
import useSWR from 'swr';

const fetcher = async (url: string) => {
  const res = await fetch(url);
  if (!res.ok) throw new Error(await res.text());
  return res.json();
};

export function usePosts(params?: { page?: number; status?: string }) {
  const searchParams = new URLSearchParams(params as Record<string, string>);
  const { data, error, isLoading, mutate } = useSWR(
    `/api/v1/posts?${searchParams}`,
    fetcher,
  );

  return {
    posts: data?.data as Post[] | undefined,
    meta: data?.meta as PaginationMeta | undefined,
    isLoading,
    error,
    refresh: mutate,
  };
}
```

### Debounce Hook
```tsx
export function useDebounce<T>(value: T, delay = 300): T {
  const [debounced, setDebounced] = useState(value);

  useEffect(() => {
    const timer = setTimeout(() => setDebounced(value), delay);
    return () => clearTimeout(timer);
  }, [value, delay]);

  return debounced;
}

// Usage: const debouncedSearch = useDebounce(searchTerm, 300);
```

### Local Storage Hook
```tsx
export function useLocalStorage<T>(key: string, initialValue: T) {
  const [value, setValue] = useState<T>(() => {
    try {
      const item = localStorage.getItem(key);
      return item ? JSON.parse(item) : initialValue;
    } catch {
      return initialValue;
    }
  });

  useEffect(() => {
    localStorage.setItem(key, JSON.stringify(value));
  }, [key, value]);

  return [value, setValue] as const;
}
```

### Media Query Hook
```tsx
export function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(false);

  useEffect(() => {
    const media = window.matchMedia(query);
    setMatches(media.matches);
    const listener = (e: MediaQueryListEvent) => setMatches(e.matches);
    media.addEventListener('change', listener);
    return () => media.removeEventListener('change', listener);
  }, [query]);

  return matches;
}

// Usage: const isMobile = useMediaQuery('(max-width: 768px)');
```

### Click Outside Hook
```tsx
export function useClickOutside(ref: RefObject<HTMLElement>, handler: () => void) {
  useEffect(() => {
    const listener = (e: MouseEvent | TouchEvent) => {
      if (!ref.current || ref.current.contains(e.target as Node)) return;
      handler();
    };
    document.addEventListener('mousedown', listener);
    document.addEventListener('touchstart', listener);
    return () => {
      document.removeEventListener('mousedown', listener);
      document.removeEventListener('touchstart', listener);
    };
  }, [ref, handler]);
}
```

---

## 3 · State Management

### Decision Tree
```
Local component state → useState / useReducer
  ↓ Need to share between siblings?
Lift state up → pass via props
  ↓ Prop drilling > 2 levels?
Context → createContext + useContext
  ↓ Frequent updates causing re-renders?
Zustand → lightweight external store
  ↓ Complex state graphs with middleware?
Redux Toolkit → full state machine
```

### Zustand (Default Choice)
```tsx
import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface AuthStore {
  user: User | null;
  accessToken: string | null;
  login: (user: User, token: string) => void;
  logout: () => void;
}

export const useAuthStore = create<AuthStore>()(
  persist(
    (set) => ({
      user: null,
      accessToken: null,
      login: (user, accessToken) => set({ user, accessToken }),
      logout: () => set({ user: null, accessToken: null }),
    }),
    { name: 'auth-storage', partialize: (state) => ({ user: state.user }) },
  ),
);

// Usage: const { user, login, logout } = useAuthStore();
// Selective subscription: const user = useAuthStore((s) => s.user);
```

### Context (For Theme/Auth/Locale)
```tsx
const ThemeContext = createContext<ThemeContextType | null>(null);

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setTheme] = useLocalStorage<'light' | 'dark'>('theme', 'light');

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
  }, [theme]);

  const toggle = () => setTheme(t => t === 'light' ? 'dark' : 'light');

  return (
    <ThemeContext.Provider value={{ theme, toggle }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme() {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error('useTheme must be used within ThemeProvider');
  return ctx;
}
```

---

## 4 · Forms (React Hook Form + Zod)

```tsx
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';

const schema = z.object({
  title: z.string().trim().min(1, 'Required').max(200),
  content: z.string().trim().min(1, 'Required'),
  tags: z.array(z.string()).max(10).default([]),
});

type FormData = z.infer<typeof schema>;

export function PostForm({ onSubmit }: { onSubmit: (data: FormData) => Promise<void> }) {
  const { register, handleSubmit, formState: { errors, isSubmitting } } = useForm<FormData>({
    resolver: zodResolver(schema),
    defaultValues: { title: '', content: '', tags: [] },
  });

  return (
    <form onSubmit={handleSubmit(onSubmit)} noValidate>
      <div>
        <label htmlFor="title">Title</label>
        <input id="title" {...register('title')} className={errors.title ? 'input-error' : ''} />
        {errors.title && <p className="error">{errors.title.message}</p>}
      </div>
      <div>
        <label htmlFor="content">Content</label>
        <textarea id="content" {...register('content')} />
        {errors.content && <p className="error">{errors.content.message}</p>}
      </div>
      <button type="submit" disabled={isSubmitting}>
        {isSubmitting ? 'Saving...' : 'Save'}
      </button>
    </form>
  );
}
```

---

## 5 · Performance Patterns

### Memoization Rules
```
✓ useMemo for expensive computations (sorting, filtering large lists)
✓ useCallback for functions passed to memoized children
✓ React.memo for components that re-render with same props
✗ Don't memo everything — it has its own cost
✗ Don't useMemo for simple values or object creation
```

### Virtualization (Large Lists)
```tsx
import { useVirtualizer } from '@tanstack/react-virtual';

function VirtualList({ items }: { items: Item[] }) {
  const parentRef = useRef<HTMLDivElement>(null);
  const virtualizer = useVirtualizer({
    count: items.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 60,
  });

  return (
    <div ref={parentRef} style={{ height: '600px', overflow: 'auto' }}>
      <div style={{ height: virtualizer.getTotalSize() }}>
        {virtualizer.getVirtualItems().map((row) => (
          <div key={row.key} style={{
            position: 'absolute', top: row.start, height: row.size, width: '100%',
          }}>
            {items[row.index].name}
          </div>
        ))}
      </div>
    </div>
  );
}
```

### Code Splitting
```tsx
// Route-based (React.lazy)
const Dashboard = lazy(() => import('./pages/Dashboard'));
const Settings = lazy(() => import('./pages/Settings'));

// In router
<Suspense fallback={<PageSkeleton />}>
  <Routes>
    <Route path="/dashboard" element={<Dashboard />} />
    <Route path="/settings" element={<Settings />} />
  </Routes>
</Suspense>
```

---

## 6 · Error Handling

### Error Boundary
```tsx
class ErrorBoundary extends Component<{ fallback: ReactNode; children: ReactNode }, { error: Error | null }> {
  state = { error: null as Error | null };

  static getDerivedStateFromError(error: Error) { return { error }; }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('ErrorBoundary caught:', error, info);
    // Report to Sentry: Sentry.captureException(error, { extra: info });
  }

  render() {
    if (this.state.error) return this.props.fallback;
    return this.props.children;
  }
}

// Usage
<ErrorBoundary fallback={<ErrorFallback />}>
  <PostList />
</ErrorBoundary>
```

### Async Error Pattern
```tsx
function useAsyncAction<T>(action: (...args: any[]) => Promise<T>) {
  const [state, setState] = useState<{ loading: boolean; error: Error | null }>({
    loading: false, error: null,
  });

  const execute = async (...args: any[]) => {
    setState({ loading: true, error: null });
    try {
      const result = await action(...args);
      setState({ loading: false, error: null });
      return result;
    } catch (err) {
      setState({ loading: false, error: err as Error });
      throw err;
    }
  };

  return { ...state, execute };
}
```

---

## 7 · API Client Pattern

```typescript
const API_BASE = import.meta.env.VITE_API_URL || '/api/v1';

class ApiClient {
  private getToken() {
    return useAuthStore.getState().accessToken;
  }

  private async request<T>(path: string, options: RequestInit = {}): Promise<T> {
    const token = this.getToken();
    const res = await fetch(`${API_BASE}${path}`, {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        ...(token && { Authorization: `Bearer ${token}` }),
        ...options.headers,
      },
      credentials: 'include',
    });

    if (res.status === 401) {
      // Try refresh, then retry once
      const refreshed = await this.refreshToken();
      if (refreshed) return this.request(path, options);
      useAuthStore.getState().logout();
      throw new Error('Session expired');
    }

    if (!res.ok) {
      const error = await res.json().catch(() => ({ error: { message: 'Request failed' } }));
      throw new ApiError(res.status, error.error);
    }

    return res.json();
  }

  get<T>(path: string) { return this.request<T>(path); }
  post<T>(path: string, body: unknown) { return this.request<T>(path, { method: 'POST', body: JSON.stringify(body) }); }
  patch<T>(path: string, body: unknown) { return this.request<T>(path, { method: 'PATCH', body: JSON.stringify(body) }); }
  delete<T>(path: string) { return this.request<T>(path, { method: 'DELETE' }); }
}

export const api = new ApiClient();
```

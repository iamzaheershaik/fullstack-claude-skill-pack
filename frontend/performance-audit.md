---
name: Performance Audit
category: frontend
version: 1.0.0
description: >
  Diagnose and fix frontend performance issues. Core Web Vitals, bundle analysis, rendering strategies, image/font optimization, and network tuning.
author: Zaheer Shaik
tags:
  - performance
  - web-vitals
  - optimization
  - lighthouse
  - frontend
---

# Performance Audit — Claude Skill

> Diagnose and fix frontend performance issues. Core Web Vitals, bundle analysis, rendering strategies, image/font optimization, network tuning.

---

## Core Directives

1. **Measure first.** Never optimize without profiling — gut feeling is wrong 80% of the time.
2. **User-perceived performance wins.** LCP and INP matter more than total bundle size.
3. **Budget, don't bloat.** Set hard limits — enforce them in CI.
4. **Progressive enhancement.** Ship critical path fast, load the rest lazily.

---

## 1 · Core Web Vitals Targets

| Metric | What It Measures | Good | Needs Work | Poor |
|---|---|---|---|---|
| **LCP** (Largest Contentful Paint) | Loading speed | ≤ 2.5s | ≤ 4.0s | > 4.0s |
| **INP** (Interaction to Next Paint) | Responsiveness | ≤ 200ms | ≤ 500ms | > 500ms |
| **CLS** (Cumulative Layout Shift) | Visual stability | ≤ 0.1 | ≤ 0.25 | > 0.25 |

### LCP Optimization
```
✓ Preload LCP image: <link rel="preload" as="image" href="hero.webp">
✓ Inline critical CSS (above-the-fold styles)
✓ Remove render-blocking resources (defer non-critical JS/CSS)
✓ Use CDN for static assets
✓ Server-side render the LCP element
✓ Optimize server response time (TTFB < 600ms)
✗ Don't lazy-load the LCP image
✗ Don't use client-side rendering for landing pages
```

### INP Optimization
```
✓ Break long tasks (>50ms) with yield / scheduler.yield()
✓ Use requestIdleCallback for non-urgent work
✓ Debounce/throttle expensive event handlers
✓ Use CSS transitions instead of JS animations
✓ Virtualize long lists (>100 items)
✓ Use web workers for heavy computation
✗ Don't block the main thread with synchronous operations
✗ Don't use layout-triggering CSS in animations
```

### CLS Optimization
```
✓ Set explicit width/height on images and videos
✓ Use aspect-ratio CSS property
✓ Reserve space for dynamic content (skeletons)
✓ Avoid inserting content above the fold after load
✓ Use font-display: swap with proper fallback sizing
✓ Use transform for animations (not width/height/top/left)
```

---

## 2 · Bundle Analysis

### Tools
```bash
# Vite — visualize bundle
npx vite-bundle-visualizer

# Webpack
npx webpack-bundle-analyzer stats.json

# Source map analysis
npx source-map-explorer dist/assets/*.js
```

### Budget Thresholds
| Asset | Max Size (gzipped) | Action If Exceeded |
|---|---|---|
| Total JS bundle | 200KB | Code-split, tree-shake, audit deps |
| Initial chunk | 100KB | Lazy-load non-critical modules |
| Single route chunk | 50KB | Split into smaller components |
| CSS total | 50KB | Purge unused, split per route |
| Hero image | 100KB | Compress, use WebP/AVIF |

### Common Bundle Bloaters
| Library | Size | Alternative |
|---|---|---|
| moment.js | 72KB | date-fns (tree-shakeable) or dayjs (2KB) |
| lodash | 72KB | lodash-es (import individual) or native |
| chart.js | 60KB | Lightweight: uPlot, or load async |
| firebase | 200KB+ | Import only used modules |

### CI Budget Enforcement
```json
// package.json
{
  "scripts": {
    "build:check": "npm run build && bundlesize",
    "bundlesize": "bundlesize"
  },
  "bundlesize": [
    { "path": "dist/assets/*.js", "maxSize": "200 kB", "compression": "gzip" },
    { "path": "dist/assets/*.css", "maxSize": "50 kB", "compression": "gzip" }
  ]
}
```

---

## 3 · Code Splitting Strategies

### Route-Based (Primary)
```tsx
import { lazy, Suspense } from 'react';

const Home = lazy(() => import('./pages/Home'));
const Dashboard = lazy(() => import('./pages/Dashboard'));
const Settings = lazy(() => import('./pages/Settings'));

function App() {
  return (
    <Suspense fallback={<PageSkeleton />}>
      <Routes>
        <Route path="/" element={<Home />} />
        <Route path="/dashboard" element={<Dashboard />} />
        <Route path="/settings" element={<Settings />} />
      </Routes>
    </Suspense>
  );
}
```

### Component-Based (Heavy UI)
```tsx
// Load editor only when needed
const RichEditor = lazy(() => import('./components/RichEditor'));

function PostForm({ mode }: { mode: 'simple' | 'rich' }) {
  return mode === 'rich' ? (
    <Suspense fallback={<TextareaSkeleton />}>
      <RichEditor />
    </Suspense>
  ) : (
    <textarea />
  );
}
```

### Library-Based (Conditional Features)
```tsx
// Load charting library only on analytics page
const Chart = lazy(() => import('recharts').then(m => ({ default: m.LineChart })));
```

---

## 4 · Image Optimization

### Format Selection
| Format | Use Case | Browser Support |
|---|---|---|
| AVIF | Photos, hero images (best compression) | 93%+ |
| WebP | General purpose fallback | 97%+ |
| SVG | Icons, logos, illustrations | 100% |
| PNG | Screenshots, images needing transparency | 100% |

### Implementation
```html
<!-- Responsive with format fallback -->
<picture>
  <source srcset="hero-400.avif 400w, hero-800.avif 800w, hero-1200.avif 1200w" type="image/avif" sizes="100vw" />
  <source srcset="hero-400.webp 400w, hero-800.webp 800w, hero-1200.webp 1200w" type="image/webp" sizes="100vw" />
  <img src="hero-800.jpg" alt="Hero description"
       width="1200" height="630" loading="lazy" decoding="async" />
</picture>

<!-- LCP image — NO lazy loading, add fetchpriority -->
<img src="hero.webp" alt="..." width="1200" height="630"
     fetchpriority="high" decoding="async" />
```

### Next.js Image
```tsx
import Image from 'next/image';

// Auto-optimizes: format, size, lazy loading
<Image src="/hero.jpg" alt="..." width={1200} height={630} priority />
```

### Image Rules
```
✓ Always set width and height (prevents CLS)
✓ Use loading="lazy" on below-fold images
✓ Use fetchpriority="high" on LCP image only
✓ Serve responsive sizes via srcset
✓ Use AVIF with WebP fallback
✓ Compress: target ~80% quality (imperceptible loss)
✗ Don't lazy-load above-fold / LCP images
✗ Don't serve 2000px images to mobile viewports
```

---

## 5 · Font Optimization

### Loading Strategy
```html
<!-- Preconnect + swap -->
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
```

### Self-Hosted (Faster)
```css
@font-face {
  font-family: 'Inter';
  src: url('/fonts/Inter-Variable.woff2') format('woff2');
  font-weight: 100 900;
  font-display: swap;
  unicode-range: U+0000-00FF, U+0131, U+0152-0153;
}
```

### Fallback Font Matching (Reduce CLS)
```css
@font-face {
  font-family: 'Inter-fallback';
  src: local('Arial');
  ascent-override: 90%;
  descent-override: 22%;
  line-gap-override: 0%;
  size-adjust: 107%;
}

body { font-family: 'Inter', 'Inter-fallback', sans-serif; }
```

---

## 6 · Rendering Strategy Decision

| Strategy | When | LCP | SEO | Dynamic |
|---|---|---|---|---|
| SSG | Content rarely changes | Best | Best | No |
| ISR | Content changes periodically | Great | Great | Partial |
| SSR | Per-request personalization | Good | Good | Yes |
| CSR | Authenticated dashboards | Poor | Poor | Yes |

### Next.js App Router Patterns
```tsx
// Static (default — SSG)
export default async function BlogPage() {
  const posts = await db.posts.findMany(); // cached at build time
  return <PostList posts={posts} />;
}

// ISR — revalidate every 60 seconds
export const revalidate = 60;

// SSR — no caching
export const dynamic = 'force-dynamic';

// Client component — CSR for interactive parts
'use client';
export function LikeButton({ postId }: { postId: string }) { ... }
```

---

## 7 · Lighthouse Audit Checklist

### Performance (Target: 90+)
```
✓ TTFB < 600ms
✓ LCP < 2.5s
✓ INP < 200ms
✓ CLS < 0.1
✓ Total blocking time < 300ms
✓ JS bundle < 200KB gzipped
```

### Accessibility (Target: 100)
```
✓ All images have alt text
✓ Color contrast ≥ 4.5:1
✓ Focusable elements have focus indicators
✓ ARIA labels on interactive elements
✓ Heading hierarchy (h1 → h2 → h3)
✓ Form inputs have labels
```

### Best Practices (Target: 100)
```
✓ HTTPS everywhere
✓ No mixed content
✓ No console errors
✓ No deprecated APIs
✓ Proper image aspect ratios
```

### SEO (Target: 100)
```
✓ <title> tag on every page
✓ <meta name="description"> on every page
✓ Canonical URL set
✓ Open Graph + Twitter Card meta tags
✓ Structured data (JSON-LD) for rich results
✓ sitemap.xml + robots.txt
✓ Proper heading hierarchy
```

---

## 8 · Network Optimization

### Resource Hints
```html
<!-- DNS prefetch for third-party domains -->
<link rel="dns-prefetch" href="//api.example.com">

<!-- Preconnect for critical third parties -->
<link rel="preconnect" href="https://api.example.com" crossorigin>

<!-- Prefetch next page (user likely to navigate) -->
<link rel="prefetch" href="/dashboard">

<!-- Preload critical resources -->
<link rel="preload" href="/fonts/inter.woff2" as="font" type="font/woff2" crossorigin>
<link rel="preload" href="/hero.webp" as="image">
```

### Caching Headers
```
# Static assets (hashed filenames)
Cache-Control: public, max-age=31536000, immutable

# HTML pages
Cache-Control: no-cache  (always revalidate)

# API responses
Cache-Control: private, max-age=60, stale-while-revalidate=300
```

### Service Worker (Offline First — Optional)
```
✓ Cache app shell (HTML, CSS, JS) for offline access
✓ Network-first for API calls, cache fallback
✓ Cache-first for static assets
✓ Background sync for offline form submissions
```

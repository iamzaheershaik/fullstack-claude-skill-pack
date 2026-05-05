# Frontend Design — Claude Skill

> Create visually stunning, modern web interfaces. Design systems, typography, color theory, layout patterns, animations, and accessibility. CSS-first with framework-agnostic principles.

---

## Core Directives

1. **Visual excellence is non-negotiable.** Every interface must look premium at first glance.
2. **Design with tokens.** Never use one-off values — everything from a system.
3. **Mobile-first, always.** Start at 320px, enhance upward.
4. **Accessibility is design.** Not an afterthought — baked into every decision.

---

## 1 · Design Token System

### Spacing Scale (4px base)
```css
:root {
  --space-1: 0.25rem;   /* 4px */
  --space-2: 0.5rem;    /* 8px */
  --space-3: 0.75rem;   /* 12px */
  --space-4: 1rem;      /* 16px */
  --space-5: 1.25rem;   /* 20px */
  --space-6: 1.5rem;    /* 24px */
  --space-8: 2rem;      /* 32px */
  --space-10: 2.5rem;   /* 40px */
  --space-12: 3rem;     /* 48px */
  --space-16: 4rem;     /* 64px */
  --space-20: 5rem;     /* 80px */
}
```

### Typography Scale (Fluid)
```css
:root {
  --font-sans: 'Inter', system-ui, -apple-system, sans-serif;
  --font-mono: 'JetBrains Mono', 'Fira Code', monospace;

  --text-xs: clamp(0.7rem, 0.65rem + 0.25vw, 0.75rem);
  --text-sm: clamp(0.8rem, 0.75rem + 0.25vw, 0.875rem);
  --text-base: clamp(0.9rem, 0.85rem + 0.25vw, 1rem);
  --text-lg: clamp(1.05rem, 0.95rem + 0.5vw, 1.125rem);
  --text-xl: clamp(1.15rem, 1rem + 0.75vw, 1.25rem);
  --text-2xl: clamp(1.4rem, 1.1rem + 1.5vw, 1.5rem);
  --text-3xl: clamp(1.7rem, 1.3rem + 2vw, 1.875rem);
  --text-4xl: clamp(2rem, 1.5rem + 2.5vw, 2.25rem);

  --leading-tight: 1.2;
  --leading-normal: 1.5;
  --leading-relaxed: 1.75;

  --tracking-tight: -0.025em;
  --tracking-normal: 0;
  --tracking-wide: 0.025em;
}
```

### Color System (HSL-based)
```css
:root {
  /* Primary — vibrant, brand-defining */
  --primary-50: hsl(230 95% 97%);
  --primary-100: hsl(230 90% 93%);
  --primary-200: hsl(230 85% 85%);
  --primary-300: hsl(230 80% 73%);
  --primary-400: hsl(230 75% 62%);
  --primary-500: hsl(230 70% 52%);   /* main */
  --primary-600: hsl(230 72% 44%);
  --primary-700: hsl(230 74% 36%);
  --primary-800: hsl(230 70% 28%);
  --primary-900: hsl(230 65% 20%);

  /* Neutral */
  --gray-50: hsl(220 20% 98%);
  --gray-100: hsl(220 17% 95%);
  --gray-200: hsl(220 15% 90%);
  --gray-300: hsl(220 13% 80%);
  --gray-400: hsl(220 11% 65%);
  --gray-500: hsl(220 10% 50%);
  --gray-600: hsl(220 12% 40%);
  --gray-700: hsl(220 14% 30%);
  --gray-800: hsl(220 16% 20%);
  --gray-900: hsl(220 18% 12%);
  --gray-950: hsl(220 20% 7%);

  /* Semantic */
  --success: hsl(150 60% 42%);
  --warning: hsl(38 92% 50%);
  --error: hsl(0 72% 51%);
  --info: hsl(200 80% 50%);

  /* Surfaces */
  --bg: var(--gray-50);
  --surface: white;
  --surface-elevated: white;
  --text-primary: var(--gray-900);
  --text-secondary: var(--gray-600);
  --text-muted: var(--gray-400);
  --border: var(--gray-200);
}

/* Dark mode */
@media (prefers-color-scheme: dark) {
  :root {
    --bg: var(--gray-950);
    --surface: var(--gray-900);
    --surface-elevated: var(--gray-800);
    --text-primary: var(--gray-50);
    --text-secondary: var(--gray-400);
    --text-muted: var(--gray-600);
    --border: var(--gray-800);
  }
}

/* Manual dark mode toggle */
[data-theme="dark"] {
  --bg: var(--gray-950);
  --surface: var(--gray-900);
  --surface-elevated: var(--gray-800);
  --text-primary: var(--gray-50);
  --text-secondary: var(--gray-400);
  --text-muted: var(--gray-600);
  --border: var(--gray-800);
}
```

### Border Radius & Shadows
```css
:root {
  --radius-sm: 0.375rem;    /* 6px */
  --radius-md: 0.5rem;      /* 8px */
  --radius-lg: 0.75rem;     /* 12px */
  --radius-xl: 1rem;        /* 16px */
  --radius-2xl: 1.5rem;     /* 24px */
  --radius-full: 9999px;

  --shadow-xs: 0 1px 2px hsl(0 0% 0% / 0.05);
  --shadow-sm: 0 1px 3px hsl(0 0% 0% / 0.1), 0 1px 2px hsl(0 0% 0% / 0.06);
  --shadow-md: 0 4px 6px hsl(0 0% 0% / 0.1), 0 2px 4px hsl(0 0% 0% / 0.06);
  --shadow-lg: 0 10px 15px hsl(0 0% 0% / 0.1), 0 4px 6px hsl(0 0% 0% / 0.05);
  --shadow-xl: 0 20px 25px hsl(0 0% 0% / 0.1), 0 10px 10px hsl(0 0% 0% / 0.04);

  /* Glassmorphism */
  --glass-bg: hsl(0 0% 100% / 0.1);
  --glass-border: hsl(0 0% 100% / 0.15);
  --glass-blur: blur(16px);
}
```

---

## 2 · Layout Patterns

### Page Layout (CSS Grid)
```css
.layout {
  display: grid;
  grid-template-rows: auto 1fr auto;  /* header, main, footer */
  min-height: 100dvh;
}

.layout-sidebar {
  display: grid;
  grid-template-columns: 280px 1fr;
  min-height: 100dvh;
}

@media (max-width: 768px) {
  .layout-sidebar { grid-template-columns: 1fr; }
}
```

### Container
```css
.container {
  width: 100%;
  max-width: 1200px;
  margin-inline: auto;
  padding-inline: var(--space-4);
}

@media (min-width: 640px)  { .container { padding-inline: var(--space-6); } }
@media (min-width: 1024px) { .container { padding-inline: var(--space-8); } }
```

### Responsive Grid
```css
.grid {
  display: grid;
  gap: var(--space-6);
  grid-template-columns: repeat(auto-fill, minmax(min(300px, 100%), 1fr));
}
```

### Breakpoints
| Name | Width | Target |
|---|---|---|
| sm | 640px | Large phones |
| md | 768px | Tablets |
| lg | 1024px | Laptops |
| xl | 1280px | Desktops |
| 2xl | 1536px | Large screens |

---

## 3 · Modern Visual Effects

### Glassmorphism Card
```css
.glass-card {
  background: var(--glass-bg);
  backdrop-filter: var(--glass-blur);
  -webkit-backdrop-filter: var(--glass-blur);
  border: 1px solid var(--glass-border);
  border-radius: var(--radius-xl);
  padding: var(--space-6);
}
```

### Gradient Backgrounds
```css
.gradient-bg {
  background: linear-gradient(135deg, hsl(230 70% 52%) 0%, hsl(280 70% 52%) 100%);
}

.gradient-text {
  background: linear-gradient(135deg, hsl(230 70% 52%), hsl(280 70% 52%));
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}

.gradient-border {
  position: relative;
  border-radius: var(--radius-lg);
  background: var(--surface);
}
.gradient-border::before {
  content: '';
  position: absolute;
  inset: -1px;
  border-radius: inherit;
  background: linear-gradient(135deg, hsl(230 70% 52%), hsl(280 70% 52%));
  z-index: -1;
}
```

### Mesh Gradient (Hero sections)
```css
.mesh-gradient {
  background-color: hsl(230 70% 52%);
  background-image:
    radial-gradient(at 40% 20%, hsl(280 70% 52%) 0px, transparent 50%),
    radial-gradient(at 80% 0%, hsl(190 80% 50%) 0px, transparent 50%),
    radial-gradient(at 0% 50%, hsl(330 70% 52%) 0px, transparent 50%),
    radial-gradient(at 80% 50%, hsl(230 70% 52%) 0px, transparent 50%),
    radial-gradient(at 0% 100%, hsl(40 80% 52%) 0px, transparent 50%);
}
```

### Glow Effect
```css
.glow {
  box-shadow: 0 0 20px hsl(230 70% 52% / 0.3), 0 0 60px hsl(230 70% 52% / 0.1);
}

.glow-hover:hover {
  box-shadow: 0 0 30px hsl(230 70% 52% / 0.4), 0 0 80px hsl(230 70% 52% / 0.15);
}
```

---

## 4 · Animation & Motion

### Transition Defaults
```css
:root {
  --ease-out: cubic-bezier(0.16, 1, 0.3, 1);
  --ease-in: cubic-bezier(0.7, 0, 0.84, 0);
  --ease-in-out: cubic-bezier(0.65, 0, 0.35, 1);
  --ease-spring: cubic-bezier(0.34, 1.56, 0.64, 1);
  --duration-fast: 150ms;
  --duration-normal: 250ms;
  --duration-slow: 400ms;
}
```

### Common Animations
```css
/* Fade in up */
@keyframes fadeInUp {
  from { opacity: 0; transform: translateY(12px); }
  to { opacity: 1; transform: translateY(0); }
}
.animate-fade-in-up { animation: fadeInUp var(--duration-normal) var(--ease-out) both; }

/* Scale in */
@keyframes scaleIn {
  from { opacity: 0; transform: scale(0.95); }
  to { opacity: 1; transform: scale(1); }
}
.animate-scale-in { animation: scaleIn var(--duration-normal) var(--ease-out) both; }

/* Slide in from right */
@keyframes slideInRight {
  from { transform: translateX(100%); }
  to { transform: translateX(0); }
}

/* Staggered children */
.stagger > * { animation: fadeInUp var(--duration-normal) var(--ease-out) both; }
.stagger > *:nth-child(1) { animation-delay: 0ms; }
.stagger > *:nth-child(2) { animation-delay: 75ms; }
.stagger > *:nth-child(3) { animation-delay: 150ms; }
.stagger > *:nth-child(4) { animation-delay: 225ms; }
.stagger > *:nth-child(5) { animation-delay: 300ms; }

/* Skeleton loading pulse */
@keyframes shimmer {
  0% { background-position: -200% 0; }
  100% { background-position: 200% 0; }
}
.skeleton {
  background: linear-gradient(90deg, var(--gray-200) 25%, var(--gray-100) 50%, var(--gray-200) 75%);
  background-size: 200% 100%;
  animation: shimmer 1.5s infinite;
  border-radius: var(--radius-sm);
}

/* Respect reduced motion */
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}
```

### Animation Rules
| Property | Duration | Easing |
|---|---|---|
| Hover states | 150ms | ease-out |
| Modals, dropdowns | 200-250ms | ease-out (in), ease-in (out) |
| Page transitions | 300-400ms | ease-in-out |
| Toasts, notifications | 300ms | spring |

```
✓ Only animate transform and opacity (GPU-accelerated)
✓ Use will-change sparingly (only on elements about to animate)
✗ Never animate width, height, top, left, margin, padding
✗ Never use animation duration > 500ms for UI elements
```

---

## 5 · Component Templates

### Button System
```css
.btn {
  display: inline-flex; align-items: center; justify-content: center; gap: var(--space-2);
  font-family: var(--font-sans); font-weight: 500; font-size: var(--text-sm);
  padding: var(--space-2) var(--space-4); border-radius: var(--radius-md);
  border: 1px solid transparent; cursor: pointer;
  transition: all var(--duration-fast) var(--ease-out);
  line-height: var(--leading-tight);
}
.btn:focus-visible { outline: 2px solid var(--primary-500); outline-offset: 2px; }
.btn:disabled { opacity: 0.5; cursor: not-allowed; }

.btn-primary { background: var(--primary-500); color: white; }
.btn-primary:hover:not(:disabled) { background: var(--primary-600); transform: translateY(-1px); box-shadow: var(--shadow-md); }

.btn-secondary { background: var(--surface); color: var(--text-primary); border-color: var(--border); }
.btn-secondary:hover:not(:disabled) { background: var(--gray-100); border-color: var(--gray-300); }

.btn-ghost { background: transparent; color: var(--text-secondary); }
.btn-ghost:hover:not(:disabled) { background: var(--gray-100); color: var(--text-primary); }

.btn-danger { background: var(--error); color: white; }
.btn-sm { padding: var(--space-1) var(--space-3); font-size: var(--text-xs); }
.btn-lg { padding: var(--space-3) var(--space-6); font-size: var(--text-base); }
```

### Input System
```css
.input {
  width: 100%;
  padding: var(--space-2) var(--space-3);
  font-family: var(--font-sans); font-size: var(--text-sm);
  background: var(--surface); color: var(--text-primary);
  border: 1px solid var(--border); border-radius: var(--radius-md);
  transition: border-color var(--duration-fast) var(--ease-out),
              box-shadow var(--duration-fast) var(--ease-out);
}
.input:focus { outline: none; border-color: var(--primary-500); box-shadow: 0 0 0 3px hsl(230 70% 52% / 0.1); }
.input-error { border-color: var(--error); }
.input-error:focus { box-shadow: 0 0 0 3px hsl(0 72% 51% / 0.1); }
```

### Card
```css
.card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius-lg);
  padding: var(--space-6);
  transition: box-shadow var(--duration-fast) var(--ease-out),
              transform var(--duration-fast) var(--ease-out);
}
.card-interactive:hover { box-shadow: var(--shadow-lg); transform: translateY(-2px); }
```

---

## 6 · Accessibility Baseline

```css
/* Focus visible — only on keyboard navigation */
:focus-visible { outline: 2px solid var(--primary-500); outline-offset: 2px; }
:focus:not(:focus-visible) { outline: none; }

/* Skip link */
.skip-link {
  position: absolute; top: -100%; left: var(--space-4);
  padding: var(--space-2) var(--space-4); background: var(--primary-500); color: white;
  border-radius: var(--radius-md); z-index: 9999;
}
.skip-link:focus { top: var(--space-4); }

/* Screen reader only */
.sr-only {
  position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px;
  overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; border: 0;
}
```

### Checklist
```
✓ Semantic HTML (nav, main, article, section, button)
✓ ARIA labels on icon-only buttons and links
✓ Color contrast ≥ 4.5:1 for text (AA), ≥ 3:1 for large text
✓ All interactive elements keyboard focusable
✓ Focus order matches visual order
✓ Form inputs have visible associated labels
✓ Alt text on meaningful images (empty alt="" for decorative)
✓ prefers-reduced-motion respected
✓ prefers-color-scheme respected
✓ Touch targets ≥ 44x44px on mobile
```

---

## 7 · Font Loading

```html
<!-- Preload critical fonts -->
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
```

### Self-hosted (Better Performance)
```css
@font-face {
  font-family: 'Inter';
  src: url('/fonts/Inter-Variable.woff2') format('woff2');
  font-weight: 100 900;
  font-display: swap;
  unicode-range: U+0000-00FF; /* Latin */
}
```

### Rules
```
✓ Use font-display: swap (visible text while loading)
✓ Preconnect to font CDN
✓ Subset fonts to needed characters
✓ Prefer variable fonts (one file, all weights)
✓ Maximum 2 font families per project
✗ Don't load weights you won't use
```

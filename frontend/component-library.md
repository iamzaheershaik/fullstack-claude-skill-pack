---
name: Component Library
category: frontend
version: 1.0.0
description: >
  Build scalable design systems and component libraries. Tokens, primitives, composition, Storybook, theming, and versioning. React + TypeScript.
author: Zaheer Shaik
tags:
  - design-system
  - components
  - react
  - storybook
  - frontend
---

# Component Library — Claude Skill

> Build scalable design systems and component libraries. Tokens, primitives, composition, Storybook, theming, versioning. React + TypeScript.

---

## Core Directives

1. **Tokens first, components second.** Design system = design tokens + composition rules.
2. **Headless over styled.** Separate behavior from presentation for maximum flexibility.
3. **API is the product.** Component props are your public contract — design them carefully.
4. **Document or it doesn't exist.** Every component needs usage examples, prop docs, and accessibility notes.

---

## 1 · Architecture Layers

```
Design Tokens        → Colors, spacing, typography, motion (CSS vars)
     ↓
Primitives           → Button, Input, Badge, Avatar (atomic elements)
     ↓
Patterns             → FormField, DataTable, Modal, Dropdown (composed)
     ↓
Features/Templates   → LoginForm, UserCard, NavBar (app-specific)
```

### File Structure
```
src/components/
├── ui/                       # Design system primitives
│   ├── button/
│   │   ├── Button.tsx        # Component
│   │   ├── Button.stories.tsx # Storybook stories
│   │   ├── Button.test.tsx    # Tests
│   │   ├── button.module.css  # Styles (or .css)
│   │   └── index.ts           # Public export
│   ├── input/
│   ├── badge/
│   ├── avatar/
│   ├── card/
│   ├── dialog/
│   └── toast/
├── patterns/                  # Composed from primitives
│   ├── form-field/
│   ├── data-table/
│   └── command-palette/
└── index.ts                   # Barrel export
```

---

## 2 · Component API Design

### Props Design Principles
```
✓ Use variant over boolean props: variant="primary" not primary={true}
✓ Use size enum: size="sm" | "md" | "lg" not small={true}
✓ Forward refs on all interactive components
✓ Spread ...rest props onto root element
✓ Support className for custom styling
✓ Use children for composition, not render props
✗ Don't use more than 8-10 props (split into sub-components)
✗ Don't accept style objects (use className + CSS vars)
```

### Button Component (Reference Implementation)
```tsx
import { forwardRef, type ButtonHTMLAttributes, type ReactNode } from 'react';
import styles from './button.module.css';

type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'danger';
type ButtonSize = 'sm' | 'md' | 'lg';

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
  loading?: boolean;
  icon?: ReactNode;
  iconPosition?: 'left' | 'right';
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ variant = 'primary', size = 'md', loading, icon, iconPosition = 'left',
     className, children, disabled, ...props }, ref) => {
    return (
      <button
        ref={ref}
        className={`${styles.btn} ${styles[variant]} ${styles[size]} ${loading ? styles.loading : ''} ${className || ''}`}
        disabled={disabled || loading}
        {...props}
      >
        {loading && <span className={styles.spinner} aria-hidden="true" />}
        {icon && iconPosition === 'left' && <span className={styles.icon}>{icon}</span>}
        {children && <span>{children}</span>}
        {icon && iconPosition === 'right' && <span className={styles.icon}>{icon}</span>}
      </button>
    );
  },
);
Button.displayName = 'Button';
```

### Dialog Component (Headless + Styled)
```tsx
import { forwardRef, useEffect, useRef, type ReactNode } from 'react';
import styles from './dialog.module.css';

interface DialogProps {
  open: boolean;
  onClose: () => void;
  children: ReactNode;
  title: string;
  description?: string;
}

export function Dialog({ open, onClose, children, title, description }: DialogProps) {
  const dialogRef = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    if (open) dialog.showModal();
    else dialog.close();
  }, [open]);

  return (
    <dialog
      ref={dialogRef}
      className={styles.dialog}
      onClose={onClose}
      aria-labelledby="dialog-title"
      aria-describedby={description ? 'dialog-desc' : undefined}
    >
      <div className={styles.content}>
        <h2 id="dialog-title" className={styles.title}>{title}</h2>
        {description && <p id="dialog-desc" className={styles.description}>{description}</p>}
        {children}
      </div>
      <div className={styles.backdrop} onClick={onClose} aria-hidden="true" />
    </dialog>
  );
}

Dialog.Actions = function Actions({ children }: { children: ReactNode }) {
  return <div className={styles.actions}>{children}</div>;
};
```

---

## 3 · Theming System

### CSS Custom Properties (Default)
```css
/* tokens/theme.css */
:root {
  --color-primary: hsl(230 70% 52%);
  --color-primary-hover: hsl(230 72% 44%);
  --color-bg: hsl(0 0% 100%);
  --color-surface: hsl(0 0% 100%);
  --color-text: hsl(220 18% 12%);
  --color-text-secondary: hsl(220 12% 40%);
  --color-border: hsl(220 15% 90%);
  --radius: 0.5rem;
  --font-sans: 'Inter', system-ui, sans-serif;
}

[data-theme="dark"] {
  --color-bg: hsl(220 20% 7%);
  --color-surface: hsl(220 18% 12%);
  --color-text: hsl(220 20% 98%);
  --color-text-secondary: hsl(220 11% 65%);
  --color-border: hsl(220 16% 20%);
}

/* Brand theming via CSS vars override */
[data-brand="startup-x"] {
  --color-primary: hsl(150 60% 42%);
  --color-primary-hover: hsl(150 65% 35%);
  --radius: 1rem;
}
```

### Theme Toggle
```tsx
export function ThemeToggle() {
  const { theme, toggle } = useTheme();
  return (
    <button onClick={toggle} aria-label={`Switch to ${theme === 'light' ? 'dark' : 'light'} mode`}>
      {theme === 'light' ? <MoonIcon /> : <SunIcon />}
    </button>
  );
}
```

---

## 4 · Storybook Setup

### Configuration
```typescript
// .storybook/main.ts
import type { StorybookConfig } from '@storybook/react-vite';

const config: StorybookConfig = {
  stories: ['../src/components/**/*.stories.@(ts|tsx)'],
  addons: [
    '@storybook/addon-essentials',
    '@storybook/addon-a11y',        // accessibility checker
    '@storybook/addon-interactions', // interaction testing
  ],
  framework: '@storybook/react-vite',
};
export default config;
```

### Story Template
```tsx
import type { Meta, StoryObj } from '@storybook/react';
import { Button } from './Button';

const meta: Meta<typeof Button> = {
  title: 'UI/Button',
  component: Button,
  tags: ['autodocs'],
  argTypes: {
    variant: { control: 'select', options: ['primary', 'secondary', 'ghost', 'danger'] },
    size: { control: 'select', options: ['sm', 'md', 'lg'] },
    loading: { control: 'boolean' },
    disabled: { control: 'boolean' },
  },
};
export default meta;

type Story = StoryObj<typeof Button>;

export const Primary: Story = {
  args: { children: 'Button', variant: 'primary' },
};

export const Secondary: Story = {
  args: { children: 'Button', variant: 'secondary' },
};

export const Loading: Story = {
  args: { children: 'Saving...', variant: 'primary', loading: true },
};

export const WithIcon: Story = {
  args: { children: 'Download', icon: <DownloadIcon />, variant: 'primary' },
};

export const AllVariants: Story = {
  render: () => (
    <div style={{ display: 'flex', gap: '8px' }}>
      <Button variant="primary">Primary</Button>
      <Button variant="secondary">Secondary</Button>
      <Button variant="ghost">Ghost</Button>
      <Button variant="danger">Danger</Button>
    </div>
  ),
};
```

---

## 5 · Accessibility in Components

### Testing with axe-core
```tsx
import { axe, toHaveNoViolations } from 'jest-axe';
expect.extend(toHaveNoViolations);

test('Button has no accessibility violations', async () => {
  const { container } = render(<Button>Click me</Button>);
  const results = await axe(container);
  expect(results).toHaveNoViolations();
});
```

### Component Accessibility Checklist
```
✓ All interactive elements are focusable
✓ Focus order matches visual order
✓ ARIA roles and labels on custom components
✓ Keyboard navigation (Enter, Space, Escape, Arrow keys)
✓ Screen reader announcements for dynamic content
✓ Color not the only indicator (use icons + text)
✓ Touch targets ≥ 44x44px on mobile
```

### ARIA Patterns for Common Components
| Component | ARIA Role | Key Interactions |
|---|---|---|
| Dialog | `dialog`, `alertdialog` | Escape to close, trap focus |
| Dropdown | `listbox`, `option` | Arrow keys to navigate, Enter to select |
| Tabs | `tablist`, `tab`, `tabpanel` | Arrow keys to switch tabs |
| Toast | `alert` or `status` | Auto-dismiss, screen reader announce |
| Tooltip | `tooltip` | Escape to dismiss, hover/focus to show |

---

## 6 · Design System Checklist

### Minimum Viable Design System
```
✓ Design tokens (colors, spacing, typography, shadows, radii)
✓ Button (primary, secondary, ghost, danger × sm, md, lg)
✓ Input (text, password, search, textarea)
✓ Badge (status colors)
✓ Avatar (image + fallback initials)
✓ Card (basic container)
✓ Dialog / Modal
✓ Toast / Notification
✓ Dropdown / Select
✓ FormField (label + input + error + description)
✓ Loading states (skeleton, spinner)
```

### Versioning & Changelog
```
✓ Semantic versioning (major.minor.patch)
✓ Major: breaking prop changes, removed components
✓ Minor: new components, new optional props
✓ Patch: bug fixes, style tweaks
✓ Maintain CHANGELOG.md with migration guides for breaking changes
```

### Documentation Per Component
```
✓ Description: what and when to use
✓ Props table: name, type, default, description
✓ Usage examples: common patterns
✓ Do/Don't: correct vs incorrect usage
✓ Accessibility notes: keyboard, screen reader behavior
✓ Related components: links to alternatives
```

# UI/UX Design-to-Code Synthesizer — Claude Skill (AI Enterprise)

> Transform design assets (wireframes, Figma exports, screenshots) into production frontend code. Vision models detect UI elements, LLMs generate HTML/CSS/React. Node.js/TypeScript.

---

## Core Directives

1. **Pixel-faithful output.** Generated code must visually match the input design — layout, spacing, colors.
2. **Semantic HTML first.** Use proper elements (`nav`, `main`, `button`) — not div soup.
3. **Responsive by default.** Every output includes mobile breakpoints. No fixed widths.
4. **Component-oriented.** Output reusable React components, not monolithic HTML pages.

---

## 1 · Image Processing Pipeline

### Element Detection
```typescript
import OpenAI from 'openai';
import { readFileSync } from 'fs';

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

interface DetectedElement {
  type: 'button' | 'input' | 'text' | 'image' | 'card' | 'nav' | 'container' | 'icon';
  label: string;
  bounds: { x: number; y: number; width: number; height: number };
  styles: { color?: string; fontSize?: string; backgroundColor?: string; borderRadius?: string };
  children?: DetectedElement[];
}

export async function detectUIElements(imagePath: string): Promise<DetectedElement[]> {
  const imageData = readFileSync(imagePath).toString('base64');
  const mimeType = imagePath.endsWith('.png') ? 'image/png' : 'image/jpeg';

  const response = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages: [
      {
        role: 'system',
        content: `You are a UI analysis expert. Analyze the screenshot and return a JSON array of detected UI elements.
For each element, identify: type, label/text, approximate bounds (x,y,width,height as percentages), and visual styles.
Group nested elements under parent containers. Return valid JSON only.`,
      },
      {
        role: 'user',
        content: [
          { type: 'image_url', image_url: { url: `data:${mimeType};base64,${imageData}` } },
          { type: 'text', text: 'Analyze this UI design. Return structured JSON of all elements.' },
        ],
      },
    ],
    max_tokens: 4000,
    temperature: 0,
    response_format: { type: 'json_object' },
  });

  const parsed = JSON.parse(response.choices[0].message.content || '{}');
  return parsed.elements || [];
}
```

### Layout Grid Extraction
```typescript
interface LayoutGrid {
  type: 'flex-row' | 'flex-col' | 'grid' | 'stack';
  columns?: number;
  gap: string;
  children: (LayoutGrid | DetectedElement)[];
}

export function inferLayout(elements: DetectedElement[]): LayoutGrid {
  const sorted = [...elements].sort((a, b) => a.bounds.y - b.bounds.y);
  const rows: DetectedElement[][] = [];
  let currentRow: DetectedElement[] = [];
  let rowY = sorted[0]?.bounds.y ?? 0;

  for (const el of sorted) {
    if (Math.abs(el.bounds.y - rowY) > 5) { // 5% threshold
      if (currentRow.length) rows.push(currentRow);
      currentRow = [el];
      rowY = el.bounds.y;
    } else {
      currentRow.push(el);
    }
  }
  if (currentRow.length) rows.push(currentRow);

  return {
    type: 'flex-col',
    gap: '1rem',
    children: rows.map(row => row.length === 1
      ? row[0]
      : { type: 'flex-row' as const, gap: '1rem', children: row.sort((a, b) => a.bounds.x - b.bounds.x) }
    ),
  };
}
```

---

## 2 · Code Generation Engine

### React Component Generator
```typescript
export async function generateReactCode(
  elements: DetectedElement[],
  options: { framework: 'react' | 'vue' | 'html'; cssMethod: 'modules' | 'tailwind' | 'vanilla'; responsive: boolean },
): Promise<{ component: string; styles: string }> {
  const layout = inferLayout(elements);

  const response = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages: [
      {
        role: 'system',
        content: `You are a senior frontend engineer. Generate production ${options.framework} code from UI element descriptions.
Rules:
- Use semantic HTML (nav, main, section, button — not divs)
- CSS: ${options.cssMethod === 'tailwind' ? 'Tailwind classes' : options.cssMethod === 'modules' ? 'CSS Modules' : 'vanilla CSS with BEM'}
- ${options.responsive ? 'Include mobile-first responsive breakpoints (640px, 768px, 1024px)' : 'Desktop only'}
- Use CSS custom properties for colors and spacing
- Include hover/focus states on interactive elements
- Add proper aria-labels on icon buttons
Return two code blocks: component file and styles file.`,
      },
      { role: 'user', content: `Generate code for this layout:\n${JSON.stringify(layout, null, 2)}` },
    ],
    max_tokens: 4000,
    temperature: 0.2,
  });

  const content = response.choices[0].message.content || '';
  const codeBlocks = content.match(/```[\w]*\n([\s\S]*?)```/g) || [];
  return {
    component: (codeBlocks[0] || '').replace(/```[\w]*\n|```/g, ''),
    styles: (codeBlocks[1] || '').replace(/```[\w]*\n|```/g, ''),
  };
}
```

### Design Token Extractor
```typescript
interface DesignTokens {
  colors: Record<string, string>;
  fontSizes: Record<string, string>;
  spacing: Record<string, string>;
  borderRadius: Record<string, string>;
}

export function extractDesignTokens(elements: DetectedElement[]): DesignTokens {
  const colors = new Set<string>();
  const fontSizes = new Set<string>();

  function collect(el: DetectedElement) {
    if (el.styles.color) colors.add(el.styles.color);
    if (el.styles.backgroundColor) colors.add(el.styles.backgroundColor);
    if (el.styles.fontSize) fontSizes.add(el.styles.fontSize);
    el.children?.forEach(collect);
  }
  elements.forEach(collect);

  return {
    colors: Object.fromEntries([...colors].map((c, i) => [`--color-${i + 1}`, c])),
    fontSizes: Object.fromEntries([...fontSizes].map((f, i) => [`--font-${i + 1}`, f])),
    spacing: { '--space-xs': '4px', '--space-sm': '8px', '--space-md': '16px', '--space-lg': '24px', '--space-xl': '48px' },
    borderRadius: { '--radius-sm': '4px', '--radius-md': '8px', '--radius-lg': '16px' },
  };
}

export function generateCSSVariables(tokens: DesignTokens): string {
  const lines = [':root {'];
  for (const [category, values] of Object.entries(tokens)) {
    lines.push(`  /* ${category} */`);
    for (const [key, val] of Object.entries(values)) lines.push(`  ${key}: ${val};`);
  }
  lines.push('}');
  return lines.join('\n');
}
```

---

## 3 · Code Refinement

### Lint & Format Pipeline
```typescript
import { execSync } from 'child_process';
import { writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';

export function refineOutput(code: { component: string; styles: string }, outputDir: string) {
  mkdirSync(outputDir, { recursive: true });

  const componentPath = join(outputDir, 'Component.tsx');
  const stylesPath = join(outputDir, 'Component.module.css');

  writeFileSync(componentPath, code.component);
  writeFileSync(stylesPath, code.styles);

  // Auto-format
  try { execSync(`npx prettier --write ${componentPath} ${stylesPath}`, { stdio: 'pipe' }); } catch {}

  // Lint check
  try {
    execSync(`npx eslint --fix ${componentPath}`, { stdio: 'pipe' });
  } catch (e: any) {
    return { success: false, errors: e.stdout?.toString() || 'Lint errors' };
  }

  return { success: true, files: [componentPath, stylesPath] };
}
```

### Accessibility Validator
```typescript
export function validateAccessibility(html: string): { issues: string[]; score: number } {
  const issues: string[] = [];

  if (!html.includes('alt=')) issues.push('Missing alt attributes on images');
  if (/<button[^>]*>(\s*<(svg|img|i)[^>]*>\s*)<\/button>/i.test(html)) {
    issues.push('Icon-only buttons missing aria-label');
  }
  if (!/<(nav|main|header|footer|section|article)/i.test(html)) {
    issues.push('No semantic HTML landmarks found');
  }
  if (/<div[^>]*onclick/i.test(html)) issues.push('Using div with onclick — use button');

  return { issues, score: Math.max(0, 100 - issues.length * 15) };
}
```

---

## 4 · Figma Integration

### Figma API Client
```typescript
interface FigmaNode {
  id: string;
  name: string;
  type: string;
  children?: FigmaNode[];
  absoluteBoundingBox?: { x: number; y: number; width: number; height: number };
  fills?: { color: { r: number; g: number; b: number; a: number } }[];
  style?: { fontSize: number; fontFamily: string; fontWeight: number };
}

export async function fetchFigmaFrame(fileKey: string, nodeId: string): Promise<FigmaNode> {
  const res = await fetch(`https://api.figma.com/v1/files/${fileKey}/nodes?ids=${nodeId}`, {
    headers: { 'X-Figma-Token': process.env.FIGMA_ACCESS_TOKEN! },
  });
  const data = await res.json();
  return data.nodes[nodeId].document;
}

export function figmaToElements(node: FigmaNode): DetectedElement[] {
  const elements: DetectedElement[] = [];

  function walk(n: FigmaNode) {
    if (n.type === 'TEXT') {
      elements.push({ type: 'text', label: n.name, bounds: toBounds(n), styles: toStyles(n) });
    } else if (n.type === 'RECTANGLE' || n.type === 'FRAME') {
      elements.push({ type: 'container', label: n.name, bounds: toBounds(n), styles: toStyles(n) });
    }
    n.children?.forEach(walk);
  }
  walk(node);
  return elements;
}

function toBounds(n: FigmaNode) {
  const bb = n.absoluteBoundingBox || { x: 0, y: 0, width: 100, height: 50 };
  return bb;
}

function toStyles(n: FigmaNode) {
  const fill = n.fills?.[0]?.color;
  return {
    backgroundColor: fill ? `rgba(${Math.round(fill.r * 255)},${Math.round(fill.g * 255)},${Math.round(fill.b * 255)},${fill.a})` : undefined,
    fontSize: n.style?.fontSize ? `${n.style.fontSize}px` : undefined,
  };
}
```

---

## 5 · Design-to-Code Checklist

```
Input Processing:
✓ Accept PNG, JPG, WebP screenshots
✓ Accept Figma file URLs (via API)
✓ Accept hand-drawn wireframes (lower accuracy expected)
✓ Detect dark mode vs light mode automatically

Code Output:
✓ Semantic HTML (nav, main, section, button)
✓ CSS custom properties for all design tokens
✓ Responsive breakpoints (mobile-first)
✓ Hover/focus states on interactive elements
✓ Accessibility: aria-labels, alt text, focus rings

Quality:
✓ Auto-format with Prettier
✓ Lint with ESLint
✓ Accessibility audit (semantic HTML, contrast)
✓ Component naming follows project conventions
✗ No inline styles — use classes or CSS modules
✗ No hardcoded pixel values for layout (use rem/%)
```

---

## Response Format

```
1. Detected elements summary (types, hierarchy)
2. Generated component code (complete, runnable)
3. Extracted design tokens (CSS variables)
4. Accessibility score and issues
```

**Never output:** inline styles, div-only markup, fixed-width layouts, missing alt text.
**Always output:** semantic HTML, responsive CSS, design tokens, accessibility report.

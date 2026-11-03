import { ChangeDetectionStrategy, Component } from '@angular/core';

export interface PixelLayer {
  tone: 'primary' | 'secondary';
  opacity: number;
  d: string;
}

const CELL = 4;
const GAP = 1;
const COLUMNS = 300;
const ROWS = 30;
const OPACITIES = [0.1, 0.18, 0.27, 0.36];

/** Small deterministic PRNG so the pattern is identical on every render and in tests. */
function random(seed: number): () => number {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * Builds a pixel mosaic that is sparse on the left (behind the title) and denser to the right.
 * Cells are grouped into one path per tone and opacity to keep the DOM small.
 */
export function buildPixelLayers(seed = 26): PixelLayer[] {
  const next = random(seed);
  const paths = new Map<string, string[]>();
  for (let column = 0; column < COLUMNS; column++) {
    const density = Math.pow(column / (COLUMNS - 1), 1.4);
    for (let row = 0; row < ROWS; row++) {
      if (next() > density) continue;
      const tone = Math.sin(column / 21 + row / 7.5) > 0.15 ? 'secondary' : 'primary';
      const level = Math.min(OPACITIES.length - 1, Math.floor(next() * OPACITIES.length));
      const key = `${tone}:${level}`;
      const size = CELL - GAP;
      const cell = `M${column * CELL} ${row * CELL}h${size}v${size}h-${size}z`;
      paths.set(key, [...(paths.get(key) ?? []), cell]);
    }
  }
  return [...paths.entries()]
    .map(([key, cells]) => {
      const [tone, level] = key.split(':');
      return { tone: tone as PixelLayer['tone'], opacity: OPACITIES[Number(level)], d: cells.join('') };
    })
    .sort((a, b) => a.opacity - b.opacity || a.tone.localeCompare(b.tone));
}

const LAYERS = buildPixelLayers();

/**
 * Decorative toolbar background drawn inline so it follows the live theme: cells are filled
 * with the Material primary and secondary system colors, so light/dark mode and the brightness
 * slider recolor it without regenerating an image.
 */
@Component({
  selector: 'app-toolbar-background',
  template: `
    <svg
      viewBox="0 0 1200 120"
      preserveAspectRatio="xMaxYMid slice"
      aria-hidden="true"
      focusable="false"
    >
      @for (layer of layers; track $index) {
        <path [class]="layer.tone" [attr.fill-opacity]="layer.opacity" [attr.d]="layer.d" />
      }
    </svg>
  `,
  styles: `
    :host {
      position: absolute;
      inset: 0;
      z-index: -1;
      overflow: hidden;
      pointer-events: none;
    }
    svg {
      display: block;
      width: 100%;
      height: 100%;
    }
    .primary {
      fill: var(--mat-sys-primary);
    }
    .secondary {
      fill: var(--mat-sys-secondary);
    }
  `,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class ToolbarBackgroundComponent {
  protected readonly layers = LAYERS;
}

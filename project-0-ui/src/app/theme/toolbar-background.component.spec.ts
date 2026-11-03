import { TestBed } from '@angular/core/testing';
import { ToolbarBackgroundComponent, buildPixelLayers } from './toolbar-background.component';

describe('ToolbarBackgroundComponent', () => {
  it('renders a decorative SVG hidden from assistive technology', () => {
    const fixture = TestBed.createComponent(ToolbarBackgroundComponent);
    fixture.detectChanges();
    const svg: SVGElement = fixture.nativeElement.querySelector('svg');
    expect(svg.getAttribute('aria-hidden')).toBe('true');
    expect(svg.getAttribute('focusable')).toBe('false');
  });

  it('draws cells in both the primary and secondary theme colors', () => {
    const fixture = TestBed.createComponent(ToolbarBackgroundComponent);
    fixture.detectChanges();
    const element: HTMLElement = fixture.nativeElement;
    expect(element.querySelectorAll('path.primary').length).toBeGreaterThan(0);
    expect(element.querySelectorAll('path.secondary').length).toBeGreaterThan(0);
    for (const path of Array.from(element.querySelectorAll('path'))) {
      expect(path.getAttribute('d')).toMatch(/^M\d/);
      expect(Number(path.getAttribute('fill-opacity'))).toBeLessThanOrEqual(0.36);
    }
  });

  it('is deterministic and keeps the left edge sparse for the title', () => {
    expect(buildPixelLayers()).toEqual(buildPixelLayers());
    const cells = buildPixelLayers().flatMap((layer) => layer.d.match(/M\d+ /g) ?? []);
    const left = cells.filter((cell) => Number(cell.slice(1)) < 240).length;
    const right = cells.filter((cell) => Number(cell.slice(1)) >= 960).length;
    expect(left).toBeLessThan(right);
  });
});

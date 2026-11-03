import { DOCUMENT } from '@angular/common';
import { Injectable, computed, inject, signal } from '@angular/core';
import { APP_NAME } from '../app-name';

export const BRIGHTNESS_STORAGE_KEY = `${APP_NAME}.brightness`;

/**
 * Persists surface brightness; the light/dark control profile follows from it.
 */
@Injectable({ providedIn: 'root' })
export class ThemeService {
  private readonly document = inject(DOCUMENT);
  private readonly level = signal(this.resolveInitialBrightness());

  readonly brightness = this.level.asReadonly();
  readonly isDark = computed(() => this.level() < 45);

  constructor() {
    this.apply();
  }

  setBrightness(value: number): void {
    if (!Number.isFinite(value)) {
      throw new RangeError('Brightness must be a finite number.');
    }
    this.level.set(Math.round(Math.min(100, Math.max(0, value))));
    this.apply();
    try {
      this.document.defaultView?.localStorage.setItem(BRIGHTNESS_STORAGE_KEY, String(this.level()));
    } catch (error) {
      console.warn('Could not save brightness preference', error);
    }
  }

  private resolveInitialBrightness(): number {
    try {
      const stored = this.document.defaultView?.localStorage.getItem(BRIGHTNESS_STORAGE_KEY);
      if (stored !== null && stored !== undefined && stored.trim() !== '') {
        const value = Number(stored);
        if (Number.isFinite(value) && value >= 0 && value <= 100) return Math.round(value);
        console.warn('Ignoring invalid stored brightness preference');
      }
    } catch (error) {
      console.warn('Could not read brightness preference', error);
    }
    const prefersDark = this.document.defaultView?.matchMedia?.('(prefers-color-scheme: dark)').matches;
    return prefersDark ? 0 : 100;
  }

  private apply(): void {
    const root = this.document.documentElement;
    root.classList.toggle('dark-theme', this.isDark());
    root.setAttribute('data-brightness', String(this.level()));
  }
}

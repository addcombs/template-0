import { TestBed } from '@angular/core/testing';
import { BRIGHTNESS_STORAGE_KEY, ThemeService } from './theme.service';

describe('ThemeService', () => {
  beforeEach(() => {
    localStorage.clear();
    document.documentElement.classList.remove('dark-theme');
  });

  it('restores a saved brightness', () => {
    localStorage.setItem(BRIGHTNESS_STORAGE_KEY, '68');
    const service = TestBed.inject(ThemeService);
    expect(service.brightness()).toBe(68);
    expect(service.isDark()).toBe(false);
    expect(document.documentElement.getAttribute('data-brightness')).toBe('68');
  });

  it('starts from the system color scheme without a saved brightness', () => {
    // jsdom may not implement matchMedia, so replace it directly rather than spying on it.
    const original = window.matchMedia;
    window.matchMedia = (() => ({ matches: true })) as unknown as typeof window.matchMedia;
    try {
      const service = TestBed.inject(ThemeService);
      expect(service.brightness()).toBe(0);
      expect(document.documentElement.classList.contains('dark-theme')).toBe(true);
    } finally {
      window.matchMedia = original;
    }
  });

  it('persists brightness and updates the document class and attribute', () => {
    const service = TestBed.inject(ThemeService);
    service.setBrightness(25);
    expect(service.brightness()).toBe(25);
    expect(service.isDark()).toBe(true);
    expect(localStorage.getItem(BRIGHTNESS_STORAGE_KEY)).toBe('25');
    expect(document.documentElement.classList.contains('dark-theme')).toBe(true);
    expect(document.documentElement.getAttribute('data-brightness')).toBe('25');
    service.setBrightness(100);
    expect(document.documentElement.classList.contains('dark-theme')).toBe(false);
  });

  it('clamps and rounds finite input and rejects nonfinite input', () => {
    const service = TestBed.inject(ThemeService);
    service.setBrightness(12.6);
    expect(service.brightness()).toBe(13);
    service.setBrightness(-1);
    expect(service.brightness()).toBe(0);
    service.setBrightness(101);
    expect(service.brightness()).toBe(100);
    expect(() => service.setBrightness(Number.NaN)).toThrow(RangeError);
    expect(() => service.setBrightness(Infinity)).toThrow(RangeError);
    expect(service.brightness()).toBe(100);
  });

  it('ignores an invalid saved brightness', () => {
    const warning = vi.spyOn(console, 'warn').mockImplementation(() => {});
    localStorage.setItem(BRIGHTNESS_STORAGE_KEY, 'invalid');
    const brightness = TestBed.inject(ThemeService).brightness();
    expect([0, 100]).toContain(brightness);
    expect(warning).toHaveBeenCalled();
    warning.mockRestore();
  });

  it('applies brightness even if persistence is unavailable and reports the failure', () => {
    const service = TestBed.inject(ThemeService);
    const warning = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const storage = vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('Storage unavailable');
    });
    try {
      service.setBrightness(50);
      expect(service.brightness()).toBe(50);
      expect(document.documentElement.getAttribute('data-brightness')).toBe('50');
      expect(warning).toHaveBeenCalledWith('Could not save brightness preference', expect.any(Error));
    } finally {
      storage.mockRestore();
      warning.mockRestore();
    }
  });
});

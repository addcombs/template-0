import { APP_DISPLAY_NAME, formatDisplayName } from './app-name';

describe('formatDisplayName', () => {
  it('formats the configured application name', () => {
    expect(APP_DISPLAY_NAME).toBe('Template 0');
  });

  it('replaces special characters with spaces and capitalizes each word', () => {
    expect(formatDisplayName('my_cool-app.v2')).toBe('My Cool App V2');
    expect(formatDisplayName('  admin   portal!! ')).toBe('Admin Portal');
    expect(formatDisplayName('café@menu')).toBe('Café Menu');
  });

  it('keeps the rest of each word unchanged', () => {
    expect(formatDisplayName('iOS-app')).toBe('IOS App');
  });
});

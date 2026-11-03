import { PROJECT_SETTINGS } from './project.settings';

/** The application's configured name (also the package and project slug), from project.json. */
export const APP_NAME = PROJECT_SETTINGS.appName;

/**
 * Formats a name for display in the toolbar title and welcome messages:
 * every character that is not a letter, digit or whitespace becomes a space,
 * repeated spaces collapse, and the first letter of each word is capitalized.
 * For example, `template-0` becomes `Template 0`.
 */
export function formatDisplayName(name: string): string {
  return name
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .split(/\s+/)
    .filter(Boolean)
    .map((word) => word.charAt(0).toLocaleUpperCase() + word.slice(1))
    .join(' ');
}

export const APP_DISPLAY_NAME = formatDisplayName(APP_NAME);

/** Shown in the footer as "Developed by <name>". */
export const DEVELOPER_NAME = PROJECT_SETTINGS.developerName;

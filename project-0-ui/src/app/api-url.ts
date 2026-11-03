import { isDevMode } from '@angular/core';
import { PROJECT_SETTINGS } from './project.settings';

// The dev server and tests use relative paths (proxy.conf.json forwards them to the local API);
// production builds call the API's own host, e.g. https://api.project-0.acombs-dev.com.
export function apiUrl(path: string): string {
  return isDevMode() ? path : PROJECT_SETTINGS.apiUrl + path;
}

import { ApplicationConfig, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideHttpClient } from '@angular/common/http';
import { MAT_TOOLTIP_DEFAULT_OPTIONS, MatTooltipDefaultOptions } from '@angular/material/tooltip';

export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideHttpClient(),
    // Tooltips let the pointer through. Otherwise one stays open while the pointer is over it, and
    // covers the control beneath, whose own tooltip then never shows.
    {
      provide: MAT_TOOLTIP_DEFAULT_OPTIONS,
      useValue: { showDelay: 0, hideDelay: 0, touchendHideDelay: 1500, disableTooltipInteractivity: true } satisfies MatTooltipDefaultOptions,
    },
  ]
};

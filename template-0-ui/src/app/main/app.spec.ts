import { BreakpointObserver } from '@angular/cdk/layout';
import { TestBed } from '@angular/core/testing';
import { signal } from '@angular/core';
import { MATERIAL_ANIMATIONS } from '@angular/material/core';
import { MatDialog, MatDialogState } from '@angular/material/dialog';
import { of } from 'rxjs';
import { App } from './app';
import { AuthService } from '../auth/auth.service';
import { AccountService, AccountDetails } from './account/account.service';
import { ApiStatusService } from './api-status/api-status.service';
import { BRIGHTNESS_STORAGE_KEY } from '../theme/theme.service';

describe('App', () => {
  const auth = {
    status: signal<'loading' | 'notConfigured' | 'signedOut' | 'signedIn' | 'invalid'>('signedIn'),
    firstName: signal(''),
    email: signal('user@example.com'),
    error: signal(''),
    busy: signal(false),
    signIn: vi.fn(),
    signOut: vi.fn(),
  };
  const account = {
    state: signal<'idle' | 'loading' | 'ready' | 'missing' | 'error'>('ready'),
    details: signal<AccountDetails | null>(null),
    editing: signal(false),
    saving: signal(false),
    error: signal(''),
    load: vi.fn(),
    open: vi.fn(() => account.editing.set(true)),
    cancel: vi.fn(() => account.editing.set(false)),
    reset: vi.fn(),
    save: vi.fn(),
  };
  const apiStatus = { status: signal<'checking' | 'up' | 'down'>('checking') };

  beforeEach(async () => {
    localStorage.clear();
    document.documentElement.classList.remove('dark-theme');
    auth.status.set('signedIn');
    auth.error.set('');
    auth.firstName.set('');
    auth.busy.set(false);
    account.state.set('ready');
    account.details.set(null);
    account.editing.set(false);
    account.saving.set(false);
    account.error.set('');
    apiStatus.status.set('checking');
    vi.clearAllMocks();
    await TestBed.configureTestingModule({
      imports: [App],
      providers: [
        { provide: BreakpointObserver, useValue: { observe: () => of({ matches: true }) } },
        { provide: AuthService, useValue: auth },
        { provide: AccountService, useValue: account },
        { provide: ApiStatusService, useValue: apiStatus },
        { provide: MATERIAL_ANIMATIONS, useValue: { animationsDisabled: true } },
      ],
    }).compileComponents();
  });

  it('starts with the sidenav closed', () => {
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    const button: HTMLButtonElement = fixture.nativeElement.querySelector('button[aria-controls="app-sidenav"]');
    expect(button.getAttribute('aria-expanded')).toBe('false');
  });

  it('credits the developer in the footer', () => {
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    const credit: HTMLElement = fixture.nativeElement.querySelector('footer.app-footer .app-credit');
    expect(credit.textContent?.trim()).toBe('Developed by Adam Combs');
    const name = credit.querySelector('a.app-credit-name') as HTMLAnchorElement;
    expect(name.textContent).toBe('Adam Combs');
    expect(name.href).toBe('https://acombs-dev.com/');
  });

  it('shows the current API health in the footer, not the toolbar', () => {
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    const icon: HTMLElement = fixture.nativeElement.querySelector('footer.app-footer .api-status');
    expect(icon).toBeTruthy();
    expect(fixture.nativeElement.querySelector('mat-toolbar .api-status')).toBeNull();
    expect(icon.getAttribute('aria-label')).toBe('Checking API status');
    expect(icon.textContent?.trim()).toBe('cloud_queue');

    apiStatus.status.set('up');
    fixture.detectChanges();
    expect(icon.getAttribute('aria-label')).toBe('API is up');
    expect(icon.textContent?.trim()).toBe('cloud_done');

    apiStatus.status.set('down');
    fixture.detectChanges();
    expect(icon.getAttribute('aria-label')).toBe('API is unreachable');
    expect(icon.textContent?.trim()).toBe('cloud_off');
  });

  it('groups technology cards into front-end, back-end, cloud, and tools tabs', async () => {
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    await fixture.whenStable();
    const tabs: HTMLElement[] = Array.from(fixture.nativeElement.querySelectorAll('[role="tab"]'));
    expect(tabs.map((tab) => tab.textContent?.trim())).toEqual(['Front-end', 'Back-end', 'Cloud', 'Tools']);
    const expected = [
      ['Angular', 'Angular Material', 'Angular CDK', 'Angular Reactive Forms', 'Angular Signals', 'TypeScript', 'RxJS', 'Sass', 'SVG',
        'Material Icons & Lato', 'Vitest', 'Angular CLI', 'Node.js & npm'],
      ['Java', 'Spring Boot', 'Spring Security', 'Spring Data JPA', 'Bean Validation', 'Spring Boot Actuator', 'Swagger UI',
        'JUnit & Mockito', 'Maven', 'Spring Boot DevTools', 'PostgreSQL', 'SQL migrations'],
      ['AWS Amplify', 'Amazon Cognito', 'Neon', 'AWS Lambda', 'Amazon CloudFront', 'Amazon S3', 'AWS Certificate Manager',
        'Amazon CloudWatch Logs'],
      ['Claude', 'PowerShell scripts', 'AWS CLI'],
    ];
    const visibleCards = (label: string): HTMLElement[] => Array.from(
      fixture.nativeElement.querySelectorAll(`section.card-grid[aria-label="${label} technologies"] mat-card`),
    );
    for (const [index, tab] of tabs.entries()) {
      tab.click();
      fixture.detectChanges();
      await fixture.whenStable();
      const label = tab.textContent!.trim();
      const cards = visibleCards(label);
      expect(cards.map((card) => card.querySelector('mat-card-title')?.textContent?.trim())).toEqual(expected[index]);
      cards.forEach((card, cardIndex) => {
        expect(card.style.getPropertyValue('--card-index')).toBe(String(cardIndex));
        expect(card.querySelector('mat-card-content p')?.textContent?.trim().length).toBeGreaterThan(50);
        const logo = card.querySelector<HTMLImageElement>('mat-card-header img.technology-logo');
        const icon = card.querySelector<HTMLElement>('mat-card-header mat-icon.technology-icon');
        expect(Boolean(logo) !== Boolean(icon)).toBe(true);
        if (logo) {
          expect(logo.getAttribute('src')).toMatch(/^logos\/[a-z-]+\.svg$/);
          expect(logo.getAttribute('alt')).toBe('');
        } else {
          expect(icon?.textContent?.trim()).toMatch(/^[a-z_]+$/);
          expect(icon?.getAttribute('aria-hidden')).toBe('true');
        }
      });
    }
    const backEnd = visibleCards('Back-end');
    expect(backEnd).toHaveLength(0);
    const tools = visibleCards('Tools');
    expect(tools[0].querySelector('mat-icon.technology-icon')?.textContent?.trim()).toBe('smart_toy');
    expect(tools[0].querySelector('mat-card-content')?.textContent).toContain('agents and templates provided by Adam Combs');
    expect(tools[1].querySelector('mat-card-content')?.textContent).toContain('scripts/start-all.ps1');
    tabs[2].click();
    fixture.detectChanges();
    await fixture.whenStable();
    const cloud = visibleCards('Cloud');
    expect(cloud[1].querySelector('img')?.getAttribute('src')).toBe('logos/amazon-cognito.svg');
    expect(cloud[2].querySelector('img')?.getAttribute('src')).toBe('logos/neon.svg');
    tabs[1].click();
    fixture.detectChanges();
    await fixture.whenStable();
    const backEndCards = visibleCards('Back-end');
    expect(backEndCards[4].querySelector('img')?.getAttribute('src')).toBe('logos/hibernate.svg');
    expect(backEndCards[5].querySelector('mat-card-content')?.textContent).toContain('health check');
    expect(backEndCards[6].querySelector('img')?.getAttribute('src')).toBe('logos/swagger.svg');
    expect(backEndCards[7].querySelector('img')?.getAttribute('src')).toBe('logos/junit.svg');
  });

  it('selects technology tabs from the side menu', async () => {
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    await fixture.whenStable();
    const navItems: HTMLElement[] = Array.from<HTMLElement>(fixture.nativeElement.querySelectorAll('mat-nav-list a[mat-list-item]')).slice(1);
    expect(navItems.map((item) => item.querySelector('[matListItemTitle]')?.textContent?.trim()))    .toEqual(['Front-end', 'Back-end', 'Cloud', 'Tools']);
    navItems[2].click();
    fixture.detectChanges();
    await fixture.whenStable();
    const selected = fixture.nativeElement.querySelector('[role="tab"][aria-selected="true"]');
    expect(selected?.textContent?.trim()).toBe('Cloud');
    expect(navItems[2].getAttribute('aria-current')).toBe('page');
    expect(navItems[0].hasAttribute('aria-current')).toBe(false);
    expect(fixture.nativeElement.querySelector('section.card-grid[aria-label="Cloud technologies"]')).not.toBeNull();
  });

  it('toggles the sidenav from the hamburger button', () => {
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    const button: HTMLButtonElement = fixture.nativeElement.querySelector('button[aria-controls="app-sidenav"]');
    button.click();
    fixture.detectChanges();
    expect(button.getAttribute('aria-expanded')).toBe('true');
  });

  it('closes the sidenav from its toolbar', () => {
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    const toggle: HTMLButtonElement = fixture.nativeElement.querySelector('button[aria-label="Toggle navigation menu"]');
    toggle.click();
    fixture.detectChanges();
    const close: HTMLButtonElement = fixture.nativeElement.querySelector('mat-sidenav button[aria-label="Close navigation menu"]');
    expect(fixture.nativeElement.querySelector('mat-sidenav mat-toolbar').textContent).toContain('Menu');
    close.click();
    fixture.detectChanges();
    expect(toggle.getAttribute('aria-expanded')).toBe('false');
  });

  it('uses an overlay sidenav on narrow screens', async () => {
    TestBed.overrideProvider(BreakpointObserver, { useValue: { observe: () => of({ matches: false }) } });
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    const sidenav = fixture.nativeElement.querySelector('mat-sidenav');
    expect(sidenav.classList.contains('mat-drawer-side')).toBe(false);
    expect(sidenav.classList.contains('mat-sidenav-fixed')).toBe(true);
    const button: HTMLButtonElement = fixture.nativeElement.querySelector('button[aria-controls="app-sidenav"]');
    button.click();
    fixture.detectChanges();
    await fixture.whenStable();
    expect(button.getAttribute('aria-expanded')).toBe('true');
    await vi.waitFor(() => expect(document.activeElement).toBe(sidenav.querySelector('h2')));
  });

  it('hides the slider until the brightness icon is clicked and toggles it closed', () => {
    localStorage.setItem(BRIGHTNESS_STORAGE_KEY, '100');
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    const toggle: HTMLButtonElement = fixture.nativeElement.querySelector('button[aria-label="Adjust brightness"]');
    const control: HTMLElement = fixture.nativeElement.querySelector('.brightness-control');
    expect(toggle.querySelector('mat-icon')?.textContent?.trim()).toBe('light_mode');
    expect(control.hidden).toBe(true);
    expect(toggle.getAttribute('aria-expanded')).toBe('false');
    toggle.click();
    fixture.detectChanges();
    expect(control.hidden).toBe(false);
    expect(toggle.getAttribute('aria-expanded')).toBe('true');
    expect(localStorage.getItem(BRIGHTNESS_STORAGE_KEY)).toBe('100');
    toggle.click();
    fixture.detectChanges();
    expect(control.hidden).toBe(true);
    expect(toggle.getAttribute('aria-expanded')).toBe('false');
  });

  it('adjusts brightness from an unlabeled horizontal slider before the theme button', () => {
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    const control: HTMLElement = fixture.nativeElement.querySelector('.brightness-control');
    (control.nextElementSibling as HTMLButtonElement).click();
    fixture.detectChanges();
    const slider: HTMLInputElement = control.querySelector('input[type="range"]')!;
    expect(slider.getAttribute('aria-orientation')).toBe('horizontal');
    expect(slider.getAttribute('aria-label')).toBe('Brightness');
    expect(control.textContent?.trim()).toBe('');
    expect(control.nextElementSibling?.getAttribute('aria-label')).toBe('Adjust brightness');
    for (const level of [0, 25, 50, 75, 100]) {
      slider.value = String(level);
      slider.dispatchEvent(new Event('input'));
      fixture.detectChanges();
      expect(slider.getAttribute('aria-valuetext')).toBe(`${level}% brightness`);
      expect(document.documentElement.getAttribute('data-brightness')).toBe(String(level));
      expect(control.nextElementSibling?.querySelector('mat-icon')?.textContent?.trim())
        .toBe(level < 45 ? 'dark_mode' : 'light_mode');
    }
  });

  it('hides app content while signed out and starts sign-in', () => {
    auth.status.set('signedOut');
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('mat-sidenav-container')).toBeNull();
    expect(fixture.nativeElement.querySelector('.card-grid')).toBeNull();
    const button: HTMLButtonElement = fixture.nativeElement.querySelector('.auth-screen button');
    button.click();
    expect(auth.signIn).toHaveBeenCalledOnce();
  });

  it('explains that authentication must be configured before sign-in', () => {
    auth.status.set('notConfigured');
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    expect(fixture.nativeElement.textContent).toContain('Authentication setup is required');
    expect(fixture.nativeElement.textContent).toContain('scripts/create-cognito-pool.ps1');
    expect(fixture.nativeElement.querySelector('mat-sidenav-container')).toBeNull();
  });

  it('shows auth errors when signed out', () => {
    auth.status.set('signedOut');
    auth.error.set('Sign-in failed.');
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('[role="alert"]').textContent).toContain('Sign-in failed.');
  });

  it('opens the in-app registration form', async () => {
    auth.status.set('signedOut');
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    const buttons: HTMLButtonElement[] = Array.from(fixture.nativeElement.querySelectorAll('button'));
    buttons.find((button) => button.textContent?.includes('Create account'))?.click();
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('app-registration')).not.toBeNull();
  });

  it('opens the profile menu and signs out', () => {
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    const button: HTMLButtonElement = fixture.nativeElement.querySelector('button[aria-label="Profile"]');
    button.click();
    fixture.detectChanges();
    const menu = document.querySelector('.mat-mdc-menu-panel');
    expect(menu?.textContent).toContain('user@example.com');
    const buttons = Array.from(menu?.querySelectorAll('button') ?? []);
    buttons.find((item) => item.textContent?.includes('Sign out'))?.click();
    expect(auth.signOut).toHaveBeenCalledOnce();
  });

  it('shows available names in the profile menu and updates when account details change', () => {
    account.details.set({ email: 'user@example.com', firstName: ' Jane ', lastName: ' Doe ', phoneNumber: null });
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    fixture.nativeElement.querySelector('button[aria-label="Profile"]').click();
    fixture.detectChanges();
    const profileName = document.querySelector('.mat-mdc-menu-panel .profile-name');
    expect(profileName?.textContent?.trim()).toBe('Jane Doe');

    account.details.set({ email: 'user@example.com', firstName: null, lastName: 'Doe', phoneNumber: null });
    fixture.detectChanges();
    expect(profileName?.textContent?.trim()).toBe('Doe');

    account.details.set({ email: 'user@example.com', firstName: 'Jane', lastName: '  ', phoneNumber: null });
    fixture.detectChanges();
    expect(profileName?.textContent?.trim()).toBe('Jane');

    account.details.set({ email: 'user@example.com', firstName: ' ', lastName: null, phoneNumber: null });
    fixture.detectChanges();
    expect(profileName?.textContent?.trim()).toBe('user@example.com');
  });

  it('uses the Cognito first name when account details have no first name', () => {
    auth.firstName.set('Alex');
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    fixture.nativeElement.querySelector('button[aria-label="Profile"]').click();
    fixture.detectChanges();
    expect(document.querySelector('.mat-mdc-menu-panel .profile-name')?.textContent?.trim()).toBe('Alex');
  });

  it('opens account details from the profile menu', () => {
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    fixture.nativeElement.querySelector('button[aria-label="Profile"]').click();
    fixture.detectChanges();
    const buttons = Array.from(document.querySelectorAll('.mat-mdc-menu-panel button'));
    (buttons.find((item) => item.textContent?.includes('Account details')) as HTMLButtonElement).click();
    fixture.detectChanges();
    expect(account.open).toHaveBeenCalledOnce();
    expect(document.querySelector('[role="dialog"]')?.textContent).toContain('Account details');
  });

  it('places a more-options menu last in the toolbar with API docs and About', () => {
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    const toolbarButtons = fixture.nativeElement.querySelectorAll('.app-content > .app-toolbar > button');
    const more: HTMLButtonElement = toolbarButtons[toolbarButtons.length - 1];
    expect(more.getAttribute('aria-label')).toBe('More options');
    more.click();
    fixture.detectChanges();
    const panel = document.querySelector('.mat-mdc-menu-panel');
    const apiDocs = panel?.querySelector<HTMLAnchorElement>('a[mat-menu-item]');
    expect(apiDocs?.textContent).toContain('API docs');
    expect(apiDocs?.getAttribute('href')).toBe('/swagger-ui.html');
    expect(apiDocs?.getAttribute('target')).toBe('_blank');
    expect(apiDocs?.getAttribute('rel')).toBe('noopener');
    const about = Array.from(panel?.querySelectorAll('button') ?? []).find((item) => item.textContent?.includes('About'));
    about?.click();
    fixture.detectChanges();
    expect(document.querySelector('[role="dialog"] h2')?.textContent).toContain('About');
  });

  it('shows onboarding when account details are missing', () => {
    account.state.set('missing');
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    const dialog = document.querySelector('[role="dialog"]') as HTMLElement;
    expect(dialog.textContent).toContain('Complete your account details');
    const email = dialog.querySelector('textarea.account-email') as HTMLTextAreaElement;
    expect(email.value).toBe('user@example.com');
    expect(email.readOnly).toBe(true);
    dialog.querySelector('form')?.dispatchEvent(new Event('submit'));
    expect(account.save).not.toHaveBeenCalled();
    expect(TestBed.inject(MatDialog).openDialogs[0].disableClose).toBe(true);
    Array.from(dialog.querySelectorAll('button')).find((button) => button.textContent?.includes('Sign out'))?.click();
    expect(auth.signOut).toHaveBeenCalledOnce();
  });

  it('shows a retry action when loading fails', () => {
    account.state.set('error');
    account.error.set('Could not load account details.');
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    fixture.nativeElement.querySelector('main button').click();
    expect(account.load).toHaveBeenCalled();
  });

  it('edits account details and submits trimmed values', () => {
    account.editing.set(true);
    account.details.set({ email: 'user@example.com', firstName: 'Old', lastName: 'Name', phoneNumber: null });
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    const dialog = document.querySelector('[role="dialog"]') as HTMLElement;
    const first = dialog.querySelector('input[formControlName="firstName"]') as HTMLInputElement;
    const last = dialog.querySelector('input[formControlName="lastName"]') as HTMLInputElement;
    const phone = dialog.querySelector('input[formControlName="phoneNumber"]') as HTMLInputElement;
    expect(first.value).toBe('Old');
    first.value = ' Jane ';
    last.value = ' Doe ';
    phone.value = ' 123 ';
    for (const input of [first, last, phone]) input.dispatchEvent(new Event('input'));
    dialog.querySelector('form')?.dispatchEvent(new Event('submit'));
    expect(account.save).toHaveBeenCalledWith({ firstName: 'Jane', lastName: 'Doe', phoneNumber: '123' });
    const buttons = Array.from(dialog.querySelectorAll('button'));
    buttons.find((button) => button.textContent?.includes('Cancel'))?.click();
    expect(account.cancel).toHaveBeenCalledOnce();
  });

  it('only enables account Save when normalized form values change', () => {
    account.editing.set(true);
    account.details.set({ email: 'user@example.com', firstName: 'Jane', lastName: 'Doe', phoneNumber: null });
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    const dialog = document.querySelector('[role="dialog"]') as HTMLElement;
    const save = dialog.querySelector('button[type="submit"]') as HTMLButtonElement;
    const first = dialog.querySelector('input[formControlName="firstName"]') as HTMLInputElement;
    const phone = dialog.querySelector('input[formControlName="phoneNumber"]') as HTMLInputElement;
    expect(save.disabled).toBe(true);
    dialog.querySelector('form')?.dispatchEvent(new Event('submit'));
    expect(account.save).not.toHaveBeenCalled();

    first.value = ' Jane ';
    first.dispatchEvent(new Event('input'));
    fixture.detectChanges();
    expect(save.disabled).toBe(true);

    phone.value = '123';
    phone.dispatchEvent(new Event('input'));
    fixture.detectChanges();
    expect(save.disabled).toBe(false);

    account.saving.set(true);
    fixture.detectChanges();
    expect(save.disabled).toBe(true);
    account.saving.set(false);
    phone.value = '';
    phone.dispatchEvent(new Event('input'));
    fixture.detectChanges();
    expect(save.disabled).toBe(true);
  });

  it('enables Save for changed onboarding details', () => {
    account.state.set('missing');
    auth.firstName.set('Jane');
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    const dialog = document.querySelector('[role="dialog"]') as HTMLElement;
    const save = dialog.querySelector('button[type="submit"]') as HTMLButtonElement;
    const last = dialog.querySelector('input[formControlName="lastName"]') as HTMLInputElement;
    expect(save.disabled).toBe(true);
    last.value = 'Doe';
    last.dispatchEvent(new Event('input'));
    fixture.detectChanges();
    expect(save.disabled).toBe(false);
    dialog.querySelector('form')?.dispatchEvent(new Event('submit'));
    expect(account.save).toHaveBeenCalledWith({ firstName: 'Jane', lastName: 'Doe', phoneNumber: null });
  });

  it('closes the dialog when onboarding succeeds or the user signs out', () => {
    account.state.set('missing');
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    const dialog = TestBed.inject(MatDialog);
    expect(dialog.openDialogs.length).toBe(1);
    const onboarding = dialog.openDialogs[0];
    account.state.set('ready');
    fixture.detectChanges();
    expect(onboarding.getState()).not.toBe(MatDialogState.OPEN);

    account.editing.set(true);
    fixture.detectChanges();
    auth.status.set('signedOut');
    fixture.detectChanges();
    expect(dialog.openDialogs.every((ref) => ref.getState() !== MatDialogState.OPEN)).toBe(true);
  });

  it('keeps the form open and shows errors from account save or sign-out', () => {
    account.state.set('missing');
    account.error.set('Could not save account details.');
    auth.error.set('Sign-out failed.');
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    const dialog = document.querySelector('[role="dialog"]') as HTMLElement;
    expect(dialog.textContent).toContain('Could not save account details.');
    expect(dialog.textContent).toContain('Sign-out failed.');
    expect(TestBed.inject(MatDialog).openDialogs[0].getState()).toBe(MatDialogState.OPEN);
  });

  it('synchronizes editing when the dialog is dismissed and blocks dismissal while saving', () => {
    account.editing.set(true);
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    const dialog = TestBed.inject(MatDialog);
    const ref = dialog.openDialogs[0];
    expect(ref.disableClose).toBe(false);
    account.saving.set(true);
    fixture.detectChanges();
    expect(ref.disableClose).toBe(true);
    account.saving.set(false);
    fixture.detectChanges();
    ref.close();
    expect(account.cancel).toHaveBeenCalledOnce();
    expect(account.editing()).toBe(false);
  });

  it('greets signed-in users by first name when available', () => {
    auth.firstName.set('Alex');
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('main h1').textContent).toContain('Welcome to Template 0, Alex');
  });

  it('keeps the generic greeting for users without a first name', () => {
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('main h1').textContent.trim()).toBe('Welcome to Template 0!');
  });
});

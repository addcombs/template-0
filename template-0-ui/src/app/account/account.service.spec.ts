import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { vi } from 'vitest';

const mocks = vi.hoisted(() => ({ fetchAuthSession: vi.fn() }));
vi.mock('aws-amplify/auth', () => ({ fetchAuthSession: mocks.fetchAuthSession }));

import { AccountService } from './account.service';

describe('AccountService', () => {
  let service: AccountService;
  let http: HttpTestingController;
  const details = { email: 'user@example.com', firstName: 'Jane', lastName: 'Doe', phoneNumber: null };
  const update = { firstName: 'Jane', lastName: 'Doe', phoneNumber: null };

  beforeEach(() => {
    vi.resetAllMocks();
    mocks.fetchAuthSession.mockResolvedValue({ tokens: { idToken: 'id-token' } });
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting()] });
    service = TestBed.inject(AccountService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    try {
      http.verify();
    } finally {
      TestBed.resetTestingModule();
    }
  });

  it('loads the account with an identity token and saves updates', async () => {
    const loading = service.load();
    const get = await vi.waitFor(() => http.expectOne('/api/account'));
    expect(get.request.headers.get('Authorization')).toBe('Bearer id-token');
    get.flush(details);
    await loading;
    expect(service.state()).toBe('ready');
    service.open();
    const saving = service.save(update);
    const put = await vi.waitFor(() => http.expectOne('/api/account'));
    expect(put.request.method).toBe('PUT');
    expect(put.request.body).toEqual(update);
    put.flush(details);
    await saving;
    expect(service.details()).toEqual(details);
    expect(service.editing()).toBe(false);
  });

  it('distinguishes a missing account from a loading failure', async () => {
    const loading = service.load();
    (await vi.waitFor(() => http.expectOne('/api/account'))).flush({}, { status: 404, statusText: 'Not Found' });
    await loading;
    expect(service.state()).toBe('missing');
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const retry = service.load();
    (await vi.waitFor(() => http.expectOne('/api/account'))).flush({}, { status: 401, statusText: 'Unauthorized' });
    await retry;
    expect(service.state()).toBe('error');
    expect(service.error()).toContain('email is not verified');
    vi.restoreAllMocks();
  });

  it('does not send a pending save after the session is reset', async () => {
    let resolveSession!: (value: { tokens: { idToken: string } }) => void;
    mocks.fetchAuthSession.mockReturnValue(new Promise((resolve) => { resolveSession = resolve; }));
    const saving = service.save(update);
    service.reset();
    resolveSession({ tokens: { idToken: 'another-session-token' } });
    await saving;
    http.expectNone('/api/account');
    expect(service.state()).toBe('idle');
    expect(service.details()).toBeNull();
    expect(service.saving()).toBe(false);
  });

  it('ignores a response received after the session is reset', async () => {
    const loading = service.load();
    const request = await vi.waitFor(() => http.expectOne('/api/account'));
    service.reset();
    request.flush(details);
    await loading;
    expect(service.state()).toBe('idle');
    expect(service.details()).toBeNull();
  });
});

import { vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  configure: vi.fn(),
  setKeyValueStorage: vi.fn(),
  listen: vi.fn(),
  fetchAuthSession: vi.fn(),
  signInWithRedirect: vi.fn(),
  signOut: vi.fn(),
}));

vi.mock('aws-amplify', () => ({ Amplify: { configure: mocks.configure } }));
vi.mock('aws-amplify/auth', () => ({
  fetchAuthSession: mocks.fetchAuthSession,
  signInWithRedirect: mocks.signInWithRedirect,
  signOut: mocks.signOut,
}));
vi.mock('aws-amplify/auth/cognito', () => ({
  cognitoUserPoolsTokenProvider: { setKeyValueStorage: mocks.setKeyValueStorage },
}));
vi.mock('aws-amplify/utils', () => ({
  Hub: { listen: mocks.listen },
  sessionStorage: {},
}));
import { AUTH_CONFIG } from './auth.config';
import { AuthService } from './auth.service';

describe('AuthService', () => {
  beforeEach(() => {
    vi.resetAllMocks();
    Object.assign(AUTH_CONFIG, {
      userPoolId: 'test_pool',
      userPoolClientId: 'test_client',
      domain: 'example.auth.test',
      redirectSignIn: ['http://localhost:4200/'],
      redirectSignOut: ['http://localhost:4200/'],
    });
    window.sessionStorage.clear();
    mocks.fetchAuthSession.mockResolvedValue({});
    mocks.signInWithRedirect.mockResolvedValue(undefined);
    mocks.signOut.mockResolvedValue(undefined);
  });

  afterEach(() => window.history.replaceState({}, '', '/'));

  it('starts signed out when there is no session', async () => {
    const service = new AuthService();
    await vi.waitFor(() => expect(service.status()).toBe('signedOut'));
    expect(mocks.setKeyValueStorage).toHaveBeenCalledOnce();
    expect(mocks.configure).toHaveBeenCalledOnce();
  });

  it('does not initialize Cognito when new-app configuration is missing', async () => {
    AUTH_CONFIG.userPoolId = '';
    const service = new AuthService();
    expect(service.status()).toBe('notConfigured');
    expect(mocks.configure).not.toHaveBeenCalled();
    expect(mocks.fetchAuthSession).not.toHaveBeenCalled();
  });

  it('restores a signed-in user and displays their email', async () => {
    mocks.fetchAuthSession.mockResolvedValue({
      tokens: { idToken: { payload: { email: 'user@example.com', given_name: ' Alex ' } } },
    });
    const service = new AuthService();
    await vi.waitFor(() => expect(service.status()).toBe('signedIn'));
    expect(service.email()).toBe('user@example.com');
    expect(service.firstName()).toBe('Alex');
  });

  it('starts sign-in and signs out through Cognito', async () => {
    const service = new AuthService();
    await vi.waitFor(() => expect(service.status()).toBe('signedOut'));
    await service.signIn();
    const nonce = window.sessionStorage.getItem('template-0.auth.nonce');
    expect(nonce).toMatch(/^[a-f0-9]{64}$/);
    expect(mocks.signInWithRedirect).toHaveBeenCalledWith({ options: { nonce } });
    await service.signOut();
    expect(mocks.signInWithRedirect).toHaveBeenCalledOnce();
    expect(mocks.signOut).toHaveBeenCalledOnce();
    expect(service.status()).toBe('signedOut');
    expect(window.sessionStorage.getItem('template-0.auth.nonce')).toBeNull();
  });

  it('keeps the first name empty when it is absent from the session', async () => {
    mocks.fetchAuthSession.mockResolvedValue({
      tokens: { idToken: { payload: { email: 'user@example.com' } } },
    });
    const service = new AuthService();
    await vi.waitFor(() => expect(service.status()).toBe('signedIn'));
    expect(service.firstName()).toBe('');
  });

  it('accepts a matching login nonce and clears it', async () => {
    window.sessionStorage.setItem('template-0.auth.nonce', 'expected');
    mocks.fetchAuthSession.mockResolvedValue({
      tokens: { idToken: { payload: { nonce: 'expected' } } },
    });
    const service = new AuthService();
    await vi.waitFor(() => expect(service.status()).toBe('signedIn'));
    expect(window.sessionStorage.getItem('template-0.auth.nonce')).toBeNull();
  });

  it('blocks an unexpected login nonce until the session is cleared', async () => {
    window.sessionStorage.setItem('template-0.auth.nonce', 'expected');
    mocks.fetchAuthSession.mockResolvedValue({
      tokens: { idToken: { payload: { nonce: 'unexpected' } } },
    });
    const service = new AuthService();
    await vi.waitFor(() => expect(service.status()).toBe('invalid'));
    expect(window.sessionStorage.getItem('template-0.auth.nonce')).toBe('expected');
    await service.signOut();
    expect(window.sessionStorage.getItem('template-0.auth.nonce')).toBeNull();
  });

  it('shows errors when sign-in or session restoration fails', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    mocks.fetchAuthSession.mockRejectedValue(new Error('session failed'));
    const service = new AuthService();
    await vi.waitFor(() => expect(service.status()).toBe('signedOut'));
    expect(service.error()).toContain('Could not restore');
    mocks.signInWithRedirect.mockRejectedValue(new Error('redirect failed'));
    await service.signIn();
    expect(service.error()).toContain('Could not start sign-in');
    expect(service.busy()).toBe(false);
    vi.restoreAllMocks();
  });

  it('waits for the code exchange when returning from Cognito, keeping the nonce', async () => {
    window.history.replaceState({}, '', '/?code=abc&state=xyz');
    window.sessionStorage.setItem('template-0.auth.nonce', 'expected');
    const service = new AuthService();
    await vi.waitFor(() => expect(mocks.fetchAuthSession).toHaveBeenCalledOnce());
    await Promise.resolve();
    expect(service.status()).toBe('loading');
    expect(window.sessionStorage.getItem('template-0.auth.nonce')).toBe('expected');

    mocks.fetchAuthSession.mockResolvedValue({
      tokens: { idToken: { payload: { email: 'user@example.com', nonce: 'expected' } } },
    });
    const listener = mocks.listen.mock.calls[0][1];
    listener({ payload: { event: 'signInWithRedirect' } });
    await vi.waitFor(() => expect(service.status()).toBe('signedIn'));
    expect(service.email()).toBe('user@example.com');
    expect(window.sessionStorage.getItem('template-0.auth.nonce')).toBeNull();
  });

  it('stops waiting when the code exchange fails', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    window.history.replaceState({}, '', '/?code=abc&state=xyz');
    const service = new AuthService();
    await vi.waitFor(() => expect(mocks.fetchAuthSession).toHaveBeenCalledOnce());
    const listener = mocks.listen.mock.calls[0][1];
    listener({ payload: { event: 'signInWithRedirect_failure', data: { error: 'failed' } } });
    expect(service.status()).toBe('signedOut');
    expect(service.error()).toContain('Sign-in failed');
    vi.restoreAllMocks();
  });

  it('surfaces errors returned by the OAuth redirect', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const service = new AuthService();
    await vi.waitFor(() => expect(service.status()).toBe('signedOut'));
    const listener = mocks.listen.mock.calls[0][1];
    listener({ payload: { event: 'signInWithRedirect_failure', data: { error: 'failed' } } });
    expect(service.error()).toContain('Sign-in failed');
    expect(service.status()).toBe('signedOut');
    vi.restoreAllMocks();
  });
});

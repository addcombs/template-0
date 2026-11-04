import { Injectable, signal } from '@angular/core';
import { Amplify } from 'aws-amplify';
import { fetchAuthSession, signInWithRedirect, signOut } from 'aws-amplify/auth';
import { cognitoUserPoolsTokenProvider } from 'aws-amplify/auth/cognito';
import { Hub, sessionStorage } from 'aws-amplify/utils';
import { APP_NAME } from '../main/app-name';
import { AUTH_CONFIG, isAuthConfigured } from './auth.config';

type AuthStatus = 'loading' | 'notConfigured' | 'signedOut' | 'signedIn' | 'invalid';
const NONCE_KEY = `${APP_NAME}.auth.nonce`;

@Injectable({ providedIn: 'root' })
export class AuthService {
  readonly status = signal<AuthStatus>('loading');
  readonly email = signal('');
  readonly firstName = signal('');
  readonly error = signal('');
  readonly busy = signal(false);
  /**
   * True on the return from Cognito's sign-in page (`?code=...`). Amplify exchanges the code for
   * tokens in the background, so a session check can run before they exist; until the
   * signInWithRedirect event fires, an empty session means "not yet", not "signed out".
   */
  private awaitingRedirect = new URLSearchParams(window.location.search).has('code');

  constructor() {
    Hub.listen('auth', ({ payload }) => {
      if (payload.event === 'signInWithRedirect') {
        this.awaitingRedirect = false;
        void this.restoreSession();
      } else if (payload.event === 'signInWithRedirect_failure') {
        this.awaitingRedirect = false;
        console.error('Cognito sign-in failed', payload.data);
        this.error.set('Sign-in failed. Please try again.');
        this.status.set('signedOut');
      }
    });

    if (!isAuthConfigured(AUTH_CONFIG)) {
      this.status.set('notConfigured');
      return;
    }

    cognitoUserPoolsTokenProvider.setKeyValueStorage(sessionStorage);
    Amplify.configure({
      Auth: {
        Cognito: {
          userPoolId: AUTH_CONFIG.userPoolId,
          userPoolClientId: AUTH_CONFIG.userPoolClientId,
          loginWith: {
            oauth: {
              domain: AUTH_CONFIG.domain,
              scopes: ['openid', 'email', 'profile'],
              redirectSignIn: AUTH_CONFIG.redirectSignIn,
              redirectSignOut: AUTH_CONFIG.redirectSignOut,
              responseType: 'code',
            },
          },
        },
      },
    });
    void this.restoreSession();
  }

  async signIn(): Promise<void> {
    this.error.set('');
    this.busy.set(true);
    try {
      const bytes = crypto.getRandomValues(new Uint8Array(32));
      const nonce = Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
      window.sessionStorage.setItem(NONCE_KEY, nonce);
      await signInWithRedirect({ options: { nonce } });
    } catch (error) {
      window.sessionStorage.removeItem(NONCE_KEY);
      console.error('Could not start Cognito sign-in', error);
      this.error.set('Could not start sign-in. Please try again.');
    } finally {
      this.busy.set(false);
    }
  }

  async signOut(): Promise<void> {
    this.error.set('');
    this.busy.set(true);
    try {
      await signOut();
      window.sessionStorage.removeItem(NONCE_KEY);
      this.email.set('');
      this.firstName.set('');
      this.status.set('signedOut');
    } catch (error) {
      console.error('Cognito sign-out failed', error);
      this.error.set('Sign-out failed. Please try again.');
    } finally {
      this.busy.set(false);
    }
  }

  private async restoreSession(): Promise<void> {
    try {
      const session = await fetchAuthSession();
      if (!session.tokens) {
        // Keep the nonce and the loading state; the signInWithRedirect event checks again.
        if (this.awaitingRedirect) return;
        window.sessionStorage.removeItem(NONCE_KEY);
        this.status.set('signedOut');
        return;
      }

      const nonce = window.sessionStorage.getItem(NONCE_KEY);
      if (nonce && session.tokens.idToken?.payload['nonce'] !== nonce) {
        this.error.set('Sign-in verification failed. Clear the session and try again.');
        this.status.set('invalid');
        return;
      }
      if (nonce) {
        window.sessionStorage.removeItem(NONCE_KEY);
      }
      const email = session.tokens.idToken?.payload['email'];
      const firstName = session.tokens.idToken?.payload['given_name'];
      this.email.set(typeof email === 'string' ? email : '');
      this.firstName.set(typeof firstName === 'string' ? firstName.trim() : '');
      this.status.set('signedIn');
    } catch (error) {
      console.error('Could not restore Cognito session', error);
      this.error.set('Could not restore your session. Please try signing in again.');
      this.status.set('signedOut');
    }
  }
}

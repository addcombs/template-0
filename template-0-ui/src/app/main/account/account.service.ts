import { HttpClient, HttpErrorResponse, HttpHeaders } from '@angular/common/http';
import { Injectable, inject, signal } from '@angular/core';
import { fetchAuthSession } from 'aws-amplify/auth';
import { firstValueFrom } from 'rxjs';
import { apiUrl } from '../../api-url';

export interface AccountDetails {
  email: string;
  firstName: string | null;
  lastName: string | null;
  phoneNumber: string | null;
}

export interface AccountUpdate {
  firstName: string;
  lastName: string;
  phoneNumber: string | null;
}

type AccountState = 'idle' | 'loading' | 'ready' | 'missing' | 'error';

@Injectable({ providedIn: 'root' })
export class AccountService {
  private readonly http = inject(HttpClient);
  private generation = 0;
  readonly state = signal<AccountState>('idle');
  readonly details = signal<AccountDetails | null>(null);
  readonly editing = signal(false);
  readonly saving = signal(false);
  readonly error = signal('');

  async load(): Promise<void> {
    const generation = ++this.generation;
    this.state.set('loading');
    this.error.set('');
    this.editing.set(false);
    this.details.set(null);
    try {
      const headers = await this.authHeaders();
      if (generation !== this.generation) return;
      const details = await firstValueFrom(this.http.get<AccountDetails>(apiUrl('/api/account'), { headers }));
      if (generation !== this.generation) return;
      this.details.set(details);
      this.state.set('ready');
    } catch (error) {
      if (generation !== this.generation) return;
      if (error instanceof HttpErrorResponse && error.status === 404) {
        this.state.set('missing');
      } else {
        console.error('Could not load account details', error);
        this.error.set(this.errorMessage(error, 'Could not load account details. Please try again.'));
        this.state.set('error');
      }
    }
  }

  async save(update: AccountUpdate): Promise<void> {
    if (this.saving()) return;
    const generation = this.generation;
    this.saving.set(true);
    this.error.set('');
    try {
      const headers = await this.authHeaders();
      if (generation !== this.generation) return;
      const details = await firstValueFrom(this.http.put<AccountDetails>(apiUrl('/api/account'), update, { headers }));
      if (generation !== this.generation) return;
      this.details.set(details);
      this.editing.set(false);
      this.state.set('ready');
    } catch (error) {
      if (generation !== this.generation) return;
      console.error('Could not save account details', error);
      this.error.set(this.errorMessage(error, 'Could not save account details. Please try again.'));
    } finally {
      if (generation === this.generation) this.saving.set(false);
    }
  }

  open(): void {
    this.error.set('');
    this.editing.set(true);
  }

  cancel(): void {
    this.error.set('');
    this.editing.set(false);
  }

  reset(): void {
    this.generation++;
    this.details.set(null);
    this.editing.set(false);
    this.saving.set(false);
    this.error.set('');
    this.state.set('idle');
  }

  private async authHeaders(): Promise<HttpHeaders> {
    const session = await fetchAuthSession();
    const token = session.tokens?.idToken;
    if (!token) throw new Error('No Cognito identity token is available.');
    return new HttpHeaders({ Authorization: `Bearer ${token.toString()}` });
  }

  private errorMessage(error: unknown, fallback: string): string {
    if (error instanceof HttpErrorResponse && error.status === 401) {
      return 'Your session is invalid or your email is not verified. Sign out and sign in again.';
    }
    if (error instanceof HttpErrorResponse && error.status === 409) {
      return 'Account details conflict with an existing account. Contact an administrator.';
    }
    return fallback;
  }
}

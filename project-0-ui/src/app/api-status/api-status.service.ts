import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { catchError, map, of, switchMap, timer } from 'rxjs';
import { apiUrl } from '../api-url';

type ApiStatus = 'checking' | 'up' | 'down';

@Injectable({ providedIn: 'root' })
export class ApiStatusService {
  private readonly http = inject(HttpClient);

  readonly status = toSignal(
    timer(0, 30_000).pipe(
      switchMap(() =>
        this.http.get<{ status: string }>(apiUrl('/actuator/health')).pipe(
          map((health): ApiStatus => health?.status === 'UP' ? 'up' : 'down'),
          catchError((error) => {
            console.error('API health check failed', error);
            return of<ApiStatus>('down');
          }),
        ),
      ),
    ),
    { initialValue: 'checking' as ApiStatus },
  );
}

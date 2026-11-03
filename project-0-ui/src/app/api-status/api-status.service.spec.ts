import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { vi } from 'vitest';
import { ApiStatusService } from './api-status.service';

describe('ApiStatusService', () => {
  let service: ApiStatusService;
  let http: HttpTestingController;

  beforeEach(() => {
    vi.useFakeTimers();
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting()] });
    service = TestBed.inject(ApiStatusService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    http.verify();
    TestBed.resetTestingModule();
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it('checks immediately and follows subsequent health changes', () => {
    expect(service.status()).toBe('checking');
    vi.advanceTimersByTime(0);
    const first = http.expectOne('/actuator/health');
    expect(first.request.method).toBe('GET');
    expect(first.request.headers.has('Authorization')).toBe(false);
    first.flush({ status: 'UP' });
    expect(service.status()).toBe('up');

    vi.advanceTimersByTime(30_000);
    http.expectOne('/actuator/health').flush({ status: 'DOWN' });
    expect(service.status()).toBe('down');

    vi.advanceTimersByTime(30_000);
    http.expectOne('/actuator/health').flush({ status: 'UP' });
    expect(service.status()).toBe('up');
  });

  it('reports unreachable and invalid responses as down, then recovers', () => {
    const log = vi.spyOn(console, 'error').mockImplementation(() => {});
    vi.advanceTimersByTime(0);
    http.expectOne('/actuator/health').flush({}, { status: 503, statusText: 'Unavailable' });
    expect(service.status()).toBe('down');
    expect(log).toHaveBeenCalled();

    vi.advanceTimersByTime(30_000);
    http.expectOne('/actuator/health').flush({ status: 'UNKNOWN' });
    expect(service.status()).toBe('down');

    vi.advanceTimersByTime(30_000);
    http.expectOne('/actuator/health').flush({ status: 'UP' });
    expect(service.status()).toBe('up');
  });
});

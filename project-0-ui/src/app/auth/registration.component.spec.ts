import { TestBed } from '@angular/core/testing';
import { vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  signUp: vi.fn(),
  confirmSignUp: vi.fn(),
  resendSignUpCode: vi.fn(),
}));

vi.mock('aws-amplify/auth', () => mocks);

import { RegistrationComponent } from './registration.component';

describe('RegistrationComponent', () => {
  beforeEach(async () => {
    vi.resetAllMocks();
    mocks.signUp.mockResolvedValue({ nextStep: { signUpStep: 'CONFIRM_SIGN_UP' } });
    mocks.confirmSignUp.mockResolvedValue({ nextStep: { signUpStep: 'DONE' } });
    mocks.resendSignUpCode.mockResolvedValue({});
    await TestBed.configureTestingModule({ imports: [RegistrationComponent] }).compileComponents();
  });

  function input(fixture: ReturnType<typeof TestBed.createComponent<RegistrationComponent>>, name: string, value: string): void {
    const element: HTMLInputElement = fixture.nativeElement.querySelector(`input[formControlName="${name}"]`);
    element.value = value;
    element.dispatchEvent(new Event('input'));
    fixture.detectChanges();
  }

  function submit(fixture: ReturnType<typeof TestBed.createComponent<RegistrationComponent>>): void {
    fixture.nativeElement.querySelector('form').dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    fixture.detectChanges();
  }

  it('requires a first name, email and compliant password', () => {
    const fixture = TestBed.createComponent(RegistrationComponent);
    fixture.detectChanges();
    input(fixture, 'firstName', '   ');
    input(fixture, 'email', 'bad-email');
    input(fixture, 'password', 'short');
    submit(fixture);
    expect(mocks.signUp).not.toHaveBeenCalled();
  });

  it('registers the user, confirms the emailed code, and proceeds to sign-in', async () => {
    const fixture = TestBed.createComponent(RegistrationComponent);
    fixture.detectChanges();
    input(fixture, 'firstName', ' Alex ');
    input(fixture, 'email', 'alex@example.com');
    input(fixture, 'password', 'Password123!');
    submit(fixture);
    await vi.waitFor(() => expect(mocks.signUp).toHaveBeenCalledOnce());
    expect(mocks.signUp).toHaveBeenCalledWith({
      username: 'alex@example.com',
      password: 'Password123!',
      options: { userAttributes: { email: 'alex@example.com', given_name: 'Alex' } },
    });
    await vi.waitFor(() => {
      fixture.detectChanges();
      expect(fixture.nativeElement.textContent).toContain('Verify your email');
    });
    expect(fixture.nativeElement.querySelector('input[formControlName="email"]').value).toBe('alex@example.com');
    input(fixture, 'code', '123456');
    submit(fixture);
    await vi.waitFor(() => {
      fixture.detectChanges();
      expect(fixture.nativeElement.textContent).toContain('Account verified');
    });
    expect(mocks.confirmSignUp).toHaveBeenCalledWith({ username: 'alex@example.com', confirmationCode: '123456' });
    const onBack = vi.fn();
    fixture.componentInstance.backToSignIn.subscribe(onBack);
    fixture.nativeElement.querySelector('button').click();
    expect(onBack).toHaveBeenCalledOnce();
  });

  it('allows users to resume verification and resend a code', async () => {
    const fixture = TestBed.createComponent(RegistrationComponent);
    fixture.detectChanges();
    const buttons: HTMLButtonElement[] = Array.from(fixture.nativeElement.querySelectorAll('button'));
    buttons.find((button) => button.textContent?.includes('Already have a verification code'))?.click();
    fixture.detectChanges();
    input(fixture, 'email', 'alex@example.com');
    const resend: HTMLButtonElement = Array.from<HTMLButtonElement>(fixture.nativeElement.querySelectorAll('button'))
      .find((button) => button.textContent?.includes('Resend code'))!;
    resend.click();
    await vi.waitFor(() => {
      fixture.detectChanges();
      expect(fixture.nativeElement.textContent).toContain('A new verification code has been sent.');
    });
    expect(mocks.resendSignUpCode).toHaveBeenCalledWith({ username: 'alex@example.com' });
  });

  it('displays verification failures without marking the account verified', async () => {
    const error = new Error('incorrect');
    error.name = 'CodeMismatchException';
    mocks.confirmSignUp.mockRejectedValue(error);
    const fixture = TestBed.createComponent(RegistrationComponent);
    fixture.detectChanges();
    const buttons: HTMLButtonElement[] = Array.from(fixture.nativeElement.querySelectorAll('button'));
    buttons.find((button) => button.textContent?.includes('Already have a verification code'))?.click();
    fixture.detectChanges();
    input(fixture, 'email', 'alex@example.com');
    input(fixture, 'code', 'wrong');
    submit(fixture);
    await vi.waitFor(() => {
      fixture.detectChanges();
      expect(fixture.nativeElement.querySelector('[role="alert"]')?.textContent).toContain('incorrect');
    });
    expect(fixture.nativeElement.textContent).not.toContain('Account verified');
  });
});

import { ChangeDetectionStrategy, Component, EventEmitter, Output, signal } from '@angular/core';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { MatButtonModule } from '@angular/material/button';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { confirmSignUp, resendSignUpCode, signUp } from 'aws-amplify/auth';
import { APP_NAME } from '../app-name';

type RegistrationStep = 'register' | 'confirm' | 'complete';

@Component({
  selector: 'app-registration',
  imports: [ReactiveFormsModule, MatButtonModule, MatFormFieldModule, MatInputModule],
  templateUrl: './registration.html',
  styleUrl: './registration.scss',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class RegistrationComponent {
  @Output() readonly backToSignIn = new EventEmitter<void>();

  protected readonly appName = APP_NAME;
  protected readonly step = signal<RegistrationStep>('register');
  protected readonly busy = signal(false);
  protected readonly error = signal('');
  protected readonly message = signal('');

  protected readonly registration = new FormGroup({
    firstName: new FormControl('', {
      nonNullable: true,
      validators: [Validators.required, Validators.pattern(/\S/), Validators.maxLength(2048)],
    }),
    email: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.email] }),
    password: new FormControl('', {
      nonNullable: true,
      validators: [
        Validators.required,
        Validators.minLength(12),
        Validators.pattern(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).+$/),
      ],
    }),
  });

  protected readonly confirmation = new FormGroup({
    email: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.email] }),
    code: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.pattern(/\S/)] }),
  });

  protected async register(): Promise<void> {
    if (this.registration.invalid || this.busy()) {
      this.registration.markAllAsTouched();
      return;
    }

    this.busy.set(true);
    this.error.set('');
    this.message.set('');
    const { firstName, email, password } = this.registration.getRawValue();
    const username = email.trim();
    try {
      const result = await signUp({
        username,
        password,
        options: { userAttributes: { email: username, given_name: firstName.trim() } },
      });
      this.registration.controls.password.reset();
      if (result.nextStep.signUpStep === 'CONFIRM_SIGN_UP') {
        this.confirmation.controls.email.setValue(username);
        this.step.set('confirm');
      } else if (result.nextStep.signUpStep === 'DONE') {
        this.step.set('complete');
      } else {
        this.error.set('Registration needs an additional step that this app does not support.');
      }
    } catch (error) {
      this.error.set(this.errorMessage(error, 'Could not create your account. Please try again.'));
    } finally {
      this.busy.set(false);
    }
  }

  protected showConfirmation(): void {
    this.error.set('');
    this.message.set('');
    this.registration.controls.password.reset();
    this.confirmation.controls.email.setValue(this.registration.controls.email.value.trim());
    this.step.set('confirm');
  }

  protected async confirm(): Promise<void> {
    if (this.confirmation.invalid || this.busy()) {
      this.confirmation.markAllAsTouched();
      return;
    }
    this.busy.set(true);
    this.error.set('');
    this.message.set('');
    const { email, code } = this.confirmation.getRawValue();
    try {
      const result = await confirmSignUp({ username: email.trim(), confirmationCode: code.trim() });
      if (result.nextStep.signUpStep === 'DONE') {
        this.confirmation.controls.code.reset();
        this.step.set('complete');
      } else {
        this.error.set('Confirmation needs an additional step that this app does not support.');
      }
    } catch (error) {
      this.error.set(this.errorMessage(error, 'Could not verify your account. Please try again.'));
    } finally {
      this.busy.set(false);
    }
  }

  protected async resendCode(): Promise<void> {
    const email = this.confirmation.controls.email;
    if (email.invalid || this.busy()) {
      email.markAsTouched();
      return;
    }
    this.busy.set(true);
    this.error.set('');
    this.message.set('');
    try {
      await resendSignUpCode({ username: email.value.trim() });
      this.message.set('A new verification code has been sent.');
    } catch (error) {
      this.error.set(this.errorMessage(error, 'Could not resend the code. Please try again.'));
    } finally {
      this.busy.set(false);
    }
  }

  private errorMessage(error: unknown, fallback: string): string {
    const name = error instanceof Error ? error.name : '';
    switch (name) {
      case 'UsernameExistsException':
        return 'An account with this email already exists. Sign in or verify your account.';
      case 'CodeMismatchException':
        return 'That verification code is incorrect. Please try again.';
      case 'ExpiredCodeException':
        return 'That verification code has expired. Request a new code.';
      case 'InvalidPasswordException':
        return 'The password does not meet the requirements shown below.';
      case 'LimitExceededException':
      case 'TooManyRequestsException':
        return 'Too many requests. Please wait and try again.';
      default:
        console.error('Cognito registration error:', error);
        return fallback;
    }
  }
}

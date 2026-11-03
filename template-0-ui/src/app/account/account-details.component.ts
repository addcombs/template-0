import { ChangeDetectionStrategy, Component, OnInit, inject } from '@angular/core';
import { TextFieldModule } from '@angular/cdk/text-field';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { MatButtonModule } from '@angular/material/button';
import { MatDialogModule } from '@angular/material/dialog';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { AuthService } from '../auth/auth.service';
import { AccountService, AccountUpdate } from './account.service';

@Component({
  selector: 'app-account-details',
  imports: [ReactiveFormsModule, TextFieldModule, MatButtonModule, MatDialogModule, MatFormFieldModule, MatInputModule],
  templateUrl: './account-details.html',
  styleUrl: './account-details.scss',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class AccountDetailsComponent implements OnInit {
  protected readonly auth = inject(AuthService);
  protected readonly account = inject(AccountService);
  protected readonly form = new FormGroup({
    firstName: new FormControl('', {
      nonNullable: true,
      validators: [Validators.required, Validators.pattern(/\S/), Validators.maxLength(100)],
    }),
    lastName: new FormControl('', {
      nonNullable: true,
      validators: [Validators.required, Validators.pattern(/\S/), Validators.maxLength(100)],
    }),
    phoneNumber: new FormControl('', { nonNullable: true, validators: [Validators.maxLength(40)] }),
  });
  private initialValues: AccountUpdate = this.normalizedValues();

  ngOnInit(): void {
    const details = this.account.details();
    this.form.setValue({
      firstName: details?.firstName ?? this.auth.firstName(),
      lastName: details?.lastName ?? '',
      phoneNumber: details?.phoneNumber ?? '',
    });
    this.initialValues = this.normalizedValues();
  }

  protected hasChanges(): boolean {
    const values = this.normalizedValues();
    return values.firstName !== this.initialValues.firstName
      || values.lastName !== this.initialValues.lastName
      || values.phoneNumber !== this.initialValues.phoneNumber;
  }

  protected save(): void {
    if (this.form.invalid || this.account.saving()) {
      this.form.markAllAsTouched();
      return;
    }
    if (!this.hasChanges()) return;
    void this.account.save(this.normalizedValues());
  }

  private normalizedValues(): AccountUpdate {
    const { firstName, lastName, phoneNumber } = this.form.getRawValue();
    return {
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      phoneNumber: phoneNumber.trim() || null,
    };
  }
}

import { ChangeDetectionStrategy, Component } from '@angular/core';
import { MatButtonModule } from '@angular/material/button';
import { MatDialogModule } from '@angular/material/dialog';
import { APP_NAME } from '../app-name';

@Component({
  selector: 'app-about-dialog',
  imports: [MatButtonModule, MatDialogModule],
  template: `
    <h2 mat-dialog-title>About {{ appName }}</h2>
    <mat-dialog-content>
      <p>
        An Angular and Angular Material front end, backed by a Spring Boot account API,
        with sign-in provided by Amazon Cognito.
      </p>
      <p>The dashboard cards describe each technology and how this application uses it.</p>
    </mat-dialog-content>
    <mat-dialog-actions align="end">
      <button mat-button type="button" mat-dialog-close>Close</button>
    </mat-dialog-actions>
  `,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class AboutDialogComponent {
  protected readonly appName = APP_NAME;
}

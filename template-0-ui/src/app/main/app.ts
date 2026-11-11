import { BreakpointObserver } from '@angular/cdk/layout';
import { ChangeDetectionStrategy, Component, computed, effect, inject, signal, untracked } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { MatButtonModule } from '@angular/material/button';
import { MatCardModule } from '@angular/material/card';
import { MatDialog, MatDialogRef } from '@angular/material/dialog';
import { MatIconModule } from '@angular/material/icon';
import { MatListModule } from '@angular/material/list';
import { MatMenuModule } from '@angular/material/menu';
import { MatSidenavModule } from '@angular/material/sidenav';
import { MatTabsModule } from '@angular/material/tabs';
import { MatToolbarModule } from '@angular/material/toolbar';
import { MatTooltipModule } from '@angular/material/tooltip';
import { map } from 'rxjs';
import { ThemeService } from '../theme/theme.service';
import { AuthService } from '../auth/auth.service';
import { RegistrationComponent } from '../auth/registration';
import { AccountService } from './account/account.service';
import { AccountDetailsComponent } from './account/account-details';
import { ApiStatusService } from './api-status/api-status.service';
import { apiUrl } from '../api-url';
import { APP_DISPLAY_NAME, DEVELOPER_NAME } from './app-name';
import { AboutDialogComponent } from './about/about-dialog';
import { ToolbarBackgroundComponent } from '../theme/toolbar-background';

/** A dashboard card: shows `logo` (a local SVG in public/logos) or, when no licensed logo is bundled, a Material `icon`. */
interface Technology {
  name: string;
  logo?: string;
  icon?: string;
  description: string;
  usage: string;
}

interface TechnologyGroup {
  label: string;
  icon: string;
  technologies: Technology[];
}

@Component({
  selector: 'app-root',
  imports: [MatButtonModule, MatCardModule, MatIconModule, MatListModule, MatMenuModule, MatSidenavModule, MatTabsModule, MatToolbarModule, MatTooltipModule, RegistrationComponent, ToolbarBackgroundComponent],
  templateUrl: './app.html',
  styleUrls: ['./app.scss', './brightness-control.scss', './toolbar.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class App {
  protected readonly appName = APP_DISPLAY_NAME;
  protected readonly developerName = DEVELOPER_NAME;
  protected readonly apiDocsUrl = apiUrl('/swagger-ui.html');
  protected readonly theme = inject(ThemeService);
  protected readonly auth = inject(AuthService);
  protected readonly account = inject(AccountService);
  protected readonly apiStatus = inject(ApiStatusService).status;
  protected readonly apiStatusLabel = computed(() => {
    switch (this.apiStatus()) {
      case 'up':
        return 'API is up';
      case 'down':
        return 'API is unreachable';
      default:
        return 'Checking API status';
    }
  });
  protected readonly profileName = computed(() => {
    const details = this.account.details();
    const firstName = details?.firstName?.trim() || this.auth.firstName().trim();
    const lastName = details?.lastName?.trim();
    return [firstName, lastName].filter(Boolean).join(' ') || this.auth.email() || details?.email || '';
  });
  protected readonly registrationOpen = signal(false);
  protected readonly brightnessOpen = signal(false);
  protected readonly technologyGroups: TechnologyGroup[] = [
    {
      label: 'Front-end',
      icon: 'web',
      technologies: [
        { name: 'Angular', logo: 'logos/angular.svg', description: 'Front-end framework', usage: 'Builds the app screens and keeps the navigation, account details, and API status in sync with application state.' },
        { name: 'Angular Material', logo: 'logos/angularmaterial.svg', description: 'Material Design 3 components and theming', usage: 'Provides the toolbar, navigation drawer, dialogs, cards, buttons, and theme-aware controls; its theme-color schematic generated every palette from the single #26A1D5 primary.' },
        { name: 'Angular CDK', logo: 'logos/angularmaterial.svg', description: 'Component Dev Kit behavior primitives', usage: 'Watches screen-size breakpoints so the navigation drawer docks on wide screens and overlays on narrow ones, and auto-sizes the read-only Email field so long addresses wrap.' },
        { name: 'Angular Reactive Forms', logo: 'logos/angular.svg', description: 'Typed, validated form state', usage: 'Powers the registration and account details forms, validating required fields and lengths before submitting.' },
        { name: 'Angular Signals', logo: 'logos/angular.svg', description: 'Reactive application state', usage: 'Hold the sign-in status, account details, theme brightness, selected tab, and drawer state, so the screens update automatically whenever any of them change.' },
        { name: 'TypeScript', logo: 'logos/typescript.svg', description: 'Typed application code', usage: 'Defines types for account data and services so mistakes can be caught during development.' },
        { name: 'RxJS', logo: 'logos/rxjs.svg', description: 'Reactive HTTP and async handling', usage: 'Handles asynchronous UI events and the repeating API health check.' },
        { name: 'Sass', logo: 'logos/sass.svg', description: 'Theme and component styling', usage: 'Styles the responsive layout and generates colors for the adjustable light-to-dark theme.' },
        { name: 'SVG', icon: 'grid_on', description: 'Inline vector graphics', usage: 'Draws the toolbar\'s pixel mosaic inline, filled with the theme\'s primary and secondary colors so it follows light/dark mode and the brightness slider.' },
        { name: 'Material Icons & Lato', icon: 'font_download', description: 'Icon font and typeface from Google Fonts', usage: 'Loads the Material Icons font used for every icon in the app and the Lato typeface used for its text from Google Fonts.' },
        { name: 'Vitest', logo: 'logos/vitest.svg', description: 'Front-end unit tests', usage: 'Runs the component and service tests in a jsdom browser environment, including account requests and the API health indicator.' },
        { name: 'Angular CLI', logo: 'logos/angular.svg', description: 'Front-end build and dev server', usage: 'Builds the production bundle with esbuild, runs the tests, and serves the app locally through a Vite dev server with a proxy to the account API.' },
        { name: 'Node.js & npm', logo: 'logos/nodejs.svg', description: 'JavaScript runtime and package manager', usage: 'Runs the Angular CLI and installs the front-end dependencies listed in package.json.' },
      ],
    },
    {
      label: 'Back-end',
      icon: 'dns',
      technologies: [
        { name: 'Java', logo: 'logos/java.svg', description: 'Back-end language', usage: 'Implements the server-side account API and its validation and persistence logic.' },
        { name: 'Spring Boot', logo: 'logos/spring.svg', description: 'Account REST API', usage: 'Runs the backend, exposes the account endpoints, and loads configuration from environment variables or a local, untracked .env file.' },
        { name: 'Spring Security', logo: 'logos/spring.svg', description: 'OAuth2 resource server validating Cognito tokens', usage: 'Protects account endpoints by validating Cognito identity tokens before allowing requests.' },
        { name: 'Spring Data JPA', logo: 'logos/spring.svg', description: 'Database access and schema validation', usage: 'Provides repository access to account records; Hibernate validates the tables in the app\'s own schema, set by DATABASE_SCHEMA, at startup.' },
        { name: 'Bean Validation', logo: 'logos/hibernate.svg', description: 'Request validation with Hibernate Validator', usage: 'Rejects account updates with missing names or over-length fields before they reach the database.' },
        { name: 'Spring Boot Actuator', logo: 'logos/spring.svg', description: 'Health monitoring', usage: 'Exposes the public health check endpoint that drives the API status indicator in the footer.' },
        { name: 'Swagger UI', logo: 'logos/swagger.svg', description: 'Interactive API documentation via springdoc-openapi', usage: 'Generates OpenAPI docs from the account controller so endpoints can be explored and tried with a Cognito token.' },
        { name: 'JUnit & Mockito', logo: 'logos/junit.svg', description: 'Back-end unit tests', usage: 'Tests the account service, controller, security rules, and API docs without needing a database or Cognito.' },
        { name: 'Maven', logo: 'logos/maven.svg', description: 'Back-end build and dependency management', usage: 'Downloads Java dependencies and builds and tests the Spring Boot API.' },
        { name: 'Spring Boot DevTools', logo: 'logos/spring.svg', description: 'Development-time restarts', usage: 'Restarts the API automatically when code changes during development; it is excluded from production builds.' },
        { name: 'PostgreSQL', logo: 'logos/postgresql.svg', description: 'Account data storage', usage: 'Stores account records so profile changes remain available across sessions.' },
        { name: 'SQL migrations', logo: 'logos/postgresql.svg', description: 'Versioned database schema scripts', usage: 'Scripts in db/migrations create the app\'s schema and users table, with the unique Cognito subject and email constraints the account API expects; scripts/apply-migrations.ps1 runs them.' },
      ],
    },
    {
      label: 'Cloud',
      icon: 'cloud',
      technologies: [
        { name: 'AWS Amplify', logo: 'logos/aws-amplify.svg', description: 'Cognito client library for the browser', usage: 'Registers and confirms new users in the app, redirects to Cognito for sign-in, exchanges the returned code for tokens, and provides the session token for API requests.' },
        { name: 'Amazon Cognito', logo: 'logos/amazon-cognito.svg', description: 'Sign-in and registration', usage: 'Manages user accounts, emails registration confirmation codes, and hosts the managed login page styled in the app\'s colors; its identity tokens authorize account API requests.' },
        { name: 'Neon', logo: 'logos/neon.svg', description: 'Hosted serverless PostgreSQL', usage: 'Hosts the PostgreSQL database shared by these apps without a locally managed database server; each app keeps its tables in its own schema.' },
        { name: 'AWS Lambda', icon: 'bolt', description: 'Serverless API hosting', usage: 'Runs the Spring Boot API on Java 21 (arm64) through aws-serverless-java-container, with SnapStart to cut cold starts and a live alias behind a function URL.' },
        { name: 'Amazon CloudFront', icon: 'public', description: 'Content delivery and HTTPS', usage: 'Serves the UI at the app domain and the API at its api subdomain over HTTPS, caching the UI files and passing API requests straight to Lambda.' },
        { name: 'Amazon S3', icon: 'storage', description: 'Object storage', usage: 'Holds the built UI files in a private bucket that only CloudFront can read, and stages the API package for Lambda deployments.' },
        { name: 'AWS Certificate Manager', icon: 'verified_user', description: 'Free TLS certificates', usage: 'Issues and auto-renews the certificates for the app and API domains, validated through DNS records at the domain\'s DNS provider.' },
        { name: 'Amazon CloudWatch Logs', icon: 'receipt_long', description: 'API logging', usage: 'Collects the Lambda function\'s log output, for troubleshooting the API.' },
      ],
    },
    {
      label: 'Tools',
      icon: 'build',
      technologies: [
        { name: 'Claude', icon: 'smart_toy', description: 'AI coding agent by Anthropic', usage: 'Generated this application from the angular-app and spring-boot-app agents and templates provided by Adam Combs.' },
        { name: 'PowerShell scripts', icon: 'terminal', description: 'Setup, tests, start-up, and deployment', usage: 'scripts/start-all.ps1 installs dependencies, builds and tests both apps, then starts the API and UI; the create-* and deploy-api scripts set up AWS from project.json, and GitHub Actions builds, tests, and deploys each push to main; scripts/new-app.ps1 copies the template into a new, renamed app.' },
        { name: 'AWS CLI', icon: 'keyboard', description: 'Command-line access to AWS', usage: 'Runs every AWS step in the setup and deploy scripts, from creating the Cognito pool and certificates to uploading the UI and publishing new Lambda versions.' },
      ],
    },
  ];
  protected readonly selectedTechnologyGroup = signal(0);
  private readonly dialog = inject(MatDialog);
  private accountDialog: MatDialogRef<AccountDetailsComponent> | null = null;

  constructor() {
    effect(() => {
      const status = this.auth.status();
      untracked(() => {
        if (status === 'signedIn') {
          void this.account.load();
        } else {
          this.account.reset();
        }
      });
    });

    effect(() => {
      const signedIn = this.auth.status() === 'signedIn';
      const state = this.account.state();
      const editing = this.account.editing();
      const saving = this.account.saving();
      untracked(() => {
        const shouldOpen = signedIn && (state === 'missing' || (state === 'ready' && editing));
        if (!shouldOpen) {
          const current = this.accountDialog;
          this.accountDialog = null;
          current?.close();
          return;
        }
        if (this.accountDialog) {
          this.accountDialog.disableClose = state === 'missing' || saving;
          return;
        }
        const ref = this.dialog.open(AccountDetailsComponent, {
          width: '480px',
          maxWidth: 'calc(100vw - 32px)',
          disableClose: state === 'missing' || saving,
        });
        this.accountDialog = ref;
        ref.beforeClosed().subscribe(() => {
          if (this.accountDialog === ref) {
            this.accountDialog = null;
            if (this.account.editing()) this.account.cancel();
          }
        });
      });
    });
  }

  /** Side mode on wide screens; dismissible overlay on narrow screens. */
  protected readonly isWide = toSignal(
    inject(BreakpointObserver)
      .observe('(min-width: 960px)')
      .pipe(map((state) => state.matches)),
    { initialValue: true },
  );

  protected readonly sidenavOpened = signal(false);

  protected toggleSidenav(): void {
    this.sidenavOpened.update((opened) => !opened);
  }

  protected showTechnologyGroup(index: number): void {
    this.selectedTechnologyGroup.set(index);
    if (!this.isWide()) this.sidenavOpened.set(false);
  }

  protected openAbout(): void {
    this.dialog.open(AboutDialogComponent, { width: '420px', maxWidth: 'calc(100vw - 32px)' });
  }

}

import { PROJECT_SETTINGS } from '../project.settings';

/**
 * Public Cognito app configuration for this browser client.
 * The values come from project.settings.ts, generated from the user pool and public app client
 * the setup scripts created. Never put a client secret here.
 */
interface CognitoAuthConfig {
  userPoolId: string;
  userPoolClientId: string;
  domain: string;
  redirectSignIn: string[];
  redirectSignOut: string[];
}

export const AUTH_CONFIG: CognitoAuthConfig = { ...PROJECT_SETTINGS.auth };

export function isAuthConfigured(config: CognitoAuthConfig): boolean {
  return Boolean(
    config.userPoolId.trim() &&
      config.userPoolClientId.trim() &&
      config.domain.trim() &&
      config.redirectSignIn.length &&
      config.redirectSignOut.length,
  );
}

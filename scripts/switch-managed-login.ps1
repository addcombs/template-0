# Switches the app's Cognito sign-in domain from the classic hosted UI to managed login
# (version 2), applies Cognito's default managed-login style to the app client, and saves the full
# resulting style to logs\managed-login-branding.json (no secrets) as a starting point for
# config\managed-login-branding.json. The sign-in address does not change. Safe to re-run.
# Log: logs\managed-login.log
. "$PSScriptRoot\common.ps1" -LogName 'managed-login.log' -Title 'managed login'

$ids = Get-CognitoIds
$poolId = $ids.userPoolId; $clientId = $ids.userPoolClientId
$prefix = ($ids.domain -split '\.')[0]
Step "pool: $poolId, client: $clientId, domain: $($ids.domain)"

# --- domain -> managed login version 2 ---
$version = Invoke-AwsCli @('cognito-idp','describe-user-pool-domain','--domain',$prefix,'--query','DomainDescription.ManagedLoginVersion','--output','text')
if ($version -ne '2') {
  Invoke-AwsCli @('cognito-idp','update-user-pool-domain','--domain',$prefix,'--user-pool-id',$poolId,'--managed-login-version','2') | Out-Null
  Step "domain switched to managed login (was version $version)"
} else { Step 'domain already uses managed login' }

# --- branding style for the app client ---
$brandingId = Invoke-AwsCli @('cognito-idp','describe-managed-login-branding-by-client','--user-pool-id',$poolId,'--client-id',$clientId,'--query','ManagedLoginBranding.ManagedLoginBrandingId','--output','text') -AllowFail
if (-not $brandingId -or $brandingId -eq 'None') {
  $brandingId = Invoke-AwsCli @('cognito-idp','create-managed-login-branding','--user-pool-id',$poolId,'--client-id',$clientId,'--use-cognito-provided-values','--query','ManagedLoginBranding.ManagedLoginBrandingId','--output','text')
  Step "default managed-login style created: $brandingId"
} else { Step "managed-login style exists: $brandingId" }

$style = Invoke-AwsCli @('cognito-idp','describe-managed-login-branding','--user-pool-id',$poolId,'--managed-login-branding-id',$brandingId,'--return-merged-resources','--query','ManagedLoginBranding.Settings','--output','json') -Quiet
Write-Utf8 (Join-Path $logs 'managed-login-branding.json') $style
Step 'style saved: logs\managed-login-branding.json'
Step "DONE. Sign-in page: https://$($ids.domain)/"
Read-Host 'Press Enter to close'

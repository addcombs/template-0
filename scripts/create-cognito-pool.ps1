# Creates the app's own Cognito user pool:
#  - pool `<app>-users`: sign-in by email, self-registration, emailed verification code,
#    attributes email (required) + given_name, recovery by verified email
#  - public app client `<app>-ui` (no secret): authorization-code flow, scopes openid/email/profile,
#    callback + sign-out URLs http://localhost:4200/ and https://<domain>/
#  - sign-in domain <cognito.domainPrefix>.auth.<region>.amazoncognito.com with managed login
#    (version 2; a domain still on the classic hosted UI is switched, keeping its address)
#  - a managed-login style for the app client (Cognito's default if it has none); the current
#    style is saved in full to logs\managed-login-branding.json (no secrets) as a starting point for
#    config\managed-login-branding.json; scripts\brand-managed-login.ps1 then applies the app's colours
# Safe to re-run: reuses the pool, client, domain and style if they exist.
# Writes the IDs to state\cognito-pool.json. Log: logs\cognito-pool.log
. "$PSScriptRoot\common.ps1" -LogName 'cognito-pool.log' -Title 'Cognito pool'
$poolName = $names.UserPool
$clientName = $names.UserClient
$domainPrefix = $project.cognito.domainPrefix
$urls = @('http://localhost:4200/', "https://$domain/")

# --- user pool ---
$poolId = Invoke-AwsCli @('cognito-idp','list-user-pools','--max-results','60','--query',"UserPools[?Name=='$poolName'].Id | [0]",'--output','text')
if (-not $poolId -or $poolId -eq 'None') {
  $poolConfig = [ordered]@{
    PoolName = $poolName
    UsernameAttributes = @('email')
    AutoVerifiedAttributes = @('email')
    Schema = @(
      [ordered]@{ Name = 'email'; AttributeDataType = 'String'; Required = $true; Mutable = $true },
      [ordered]@{ Name = 'given_name'; AttributeDataType = 'String'; Required = $false; Mutable = $true }
    )
    Policies = @{ PasswordPolicy = [ordered]@{ MinimumLength = 8; RequireUppercase = $true; RequireLowercase = $true; RequireNumbers = $true; RequireSymbols = $false; TemporaryPasswordValidityDays = 7 } }
    AccountRecoverySetting = @{ RecoveryMechanisms = @(@{ Priority = 1; Name = 'verified_email' }) }
    AdminCreateUserConfig = @{ AllowAdminCreateUserOnly = $false }
    VerificationMessageTemplate = @{ DefaultEmailOption = 'CONFIRM_WITH_CODE' }
  }
  $f = Write-Json (Join-Path $logs 'cognito-pool-config.json') $poolConfig
  $poolId = Invoke-AwsCli @('cognito-idp','create-user-pool','--cli-input-json',"file://$f",'--query','UserPool.Id','--output','text')
  Step "user pool created: $poolId"
} else { Step "user pool exists: $poolId" }

# --- app client ---
$clientId = Invoke-AwsCli @('cognito-idp','list-user-pool-clients','--user-pool-id',$poolId,'--query',"UserPoolClients[?ClientName=='$clientName'].ClientId | [0]",'--output','text')
if (-not $clientId -or $clientId -eq 'None') {
  $clientConfig = [ordered]@{
    UserPoolId = $poolId
    ClientName = $clientName
    GenerateSecret = $false
    ExplicitAuthFlows = @('ALLOW_USER_SRP_AUTH', 'ALLOW_REFRESH_TOKEN_AUTH')
    SupportedIdentityProviders = @('COGNITO')
    CallbackURLs = $urls
    LogoutURLs = $urls
    AllowedOAuthFlows = @('code')
    AllowedOAuthScopes = @('openid', 'email', 'profile')
    AllowedOAuthFlowsUserPoolClient = $true
    PreventUserExistenceErrors = 'ENABLED'
    EnableTokenRevocation = $true
  }
  $f = Write-Json (Join-Path $logs 'cognito-client-config.json') $clientConfig
  $clientId = Invoke-AwsCli @('cognito-idp','create-user-pool-client','--cli-input-json',"file://$f",'--query','UserPoolClient.ClientId','--output','text')
  Step "app client created: $clientId"
} else { Step "app client exists: $clientId" }

# --- sign-in domain (managed login) ---
$signInDomain = Invoke-AwsCli @('cognito-idp','describe-user-pool','--user-pool-id',$poolId,'--query','UserPool.Domain','--output','text')
if (-not $signInDomain -or $signInDomain -eq 'None') {
  Invoke-AwsCli @('cognito-idp','create-user-pool-domain','--user-pool-id',$poolId,'--domain',$domainPrefix,'--managed-login-version','2') | Out-Null
  $signInDomain = $domainPrefix
  Step "sign-in domain created with managed login: $domainPrefix"
} else {
  $version = Invoke-AwsCli @('cognito-idp','describe-user-pool-domain','--domain',$signInDomain,'--query','DomainDescription.ManagedLoginVersion','--output','text')
  if ($version -ne '2') {
    Invoke-AwsCli @('cognito-idp','update-user-pool-domain','--domain',$signInDomain,'--user-pool-id',$poolId,'--managed-login-version','2') | Out-Null
    Step "sign-in domain switched to managed login (was version $version): $signInDomain"
  } else { Step "sign-in domain exists with managed login: $signInDomain" }
}

# --- managed-login style for the app client ---
$brandingId = Invoke-AwsCli @('cognito-idp','describe-managed-login-branding-by-client','--user-pool-id',$poolId,'--client-id',$clientId,'--query','ManagedLoginBranding.ManagedLoginBrandingId','--output','text') -AllowFail
if (-not $brandingId -or $brandingId -eq 'None') {
  $brandingId = Invoke-AwsCli @('cognito-idp','create-managed-login-branding','--user-pool-id',$poolId,'--client-id',$clientId,'--use-cognito-provided-values','--query','ManagedLoginBranding.ManagedLoginBrandingId','--output','text')
  Step "default managed-login style created: $brandingId"
} else { Step "managed-login style exists: $brandingId" }
$style = Invoke-AwsCli @('cognito-idp','describe-managed-login-branding','--user-pool-id',$poolId,'--managed-login-branding-id',$brandingId,'--return-merged-resources','--query','ManagedLoginBranding.Settings','--output','json') -Quiet
Write-Utf8 (Join-Path $logs 'managed-login-branding.json') $style
Step 'style saved: logs\managed-login-branding.json'

$result = [ordered]@{
  userPoolId = $poolId
  userPoolClientId = $clientId
  domain = "$signInDomain.auth.$awsRegion.amazoncognito.com"
  issuer = "https://cognito-idp.$awsRegion.amazonaws.com/$poolId"
}
Write-Json $cognitoStateFile $result | Out-Null
Step "issuer: $($result.issuer)"
Step "domain: $($result.domain)"
Step 'DONE. IDs saved to state\cognito-pool.json (deploy-api and start-all pass them to the API)'
Read-Host 'Press Enter to close'

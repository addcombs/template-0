# Creates the app's own Cognito user pool:
#  - pool `<app>-users`: sign-in by email, self-registration, emailed verification code,
#    attributes email (required) + given_name, recovery by verified email
#  - public app client `<app>-ui` (no secret): authorization-code flow, scopes openid/email/profile,
#    callback + sign-out URLs http://localhost:4200/ and https://<domain>/
#  - hosted sign-in domain <cognito.domainPrefix>.auth.<region>.amazoncognito.com (classic hosted UI;
#    switch-managed-login.cmd moves it to managed login)
# Safe to re-run: reuses the pool, client and domain if they exist.
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

# --- hosted sign-in domain ---
$signInDomain = Invoke-AwsCli @('cognito-idp','describe-user-pool','--user-pool-id',$poolId,'--query','UserPool.Domain','--output','text')
if (-not $signInDomain -or $signInDomain -eq 'None') {
  Invoke-AwsCli @('cognito-idp','create-user-pool-domain','--user-pool-id',$poolId,'--domain',$domainPrefix,'--managed-login-version','1') | Out-Null
  $signInDomain = $domainPrefix
  Step "sign-in domain created: $domainPrefix"
} else { Step "sign-in domain exists: $signInDomain" }

$result = [ordered]@{
  userPoolId = $poolId
  userPoolClientId = $clientId
  domain = "$signInDomain.auth.$awsRegion.amazoncognito.com"
  issuer = "https://cognito-idp.$awsRegion.amazonaws.com/$poolId"
}
Write-Json $cognitoStateFile $result | Out-Null
Step "issuer: $($result.issuer)"
Step "domain: $($result.domain)"
Step 'DONE. IDs saved to state\cognito-pool.json (the API .env needs COGNITO_ISSUER and COGNITO_CLIENT_ID from it)'
Read-Host 'Press Enter to close'

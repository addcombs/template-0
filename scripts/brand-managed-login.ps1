# Applies the app's colours from config\managed-login-branding.json to its Cognito managed-login
# style (for template-0: primary #00668a/#7bd0ff, secondary #006b58/#37debb, app-like neutral
# backgrounds, light/dark following the visitor's system setting). Run switch-managed-login.cmd first.
# Log: logs\managed-login.log (appended)
. "$PSScriptRoot\common.ps1" -LogName 'managed-login.log' -AppendLog
$ids = Get-CognitoIds
$id = Invoke-AwsCli @('cognito-idp','describe-managed-login-branding-by-client','--user-pool-id',$ids.userPoolId,'--client-id',$ids.userPoolClientId,'--query','ManagedLoginBranding.ManagedLoginBrandingId','--output','text')
$settings = Join-Path $config 'managed-login-branding.json'
if (-not (Test-Path $settings)) { Fail 'config\managed-login-branding.json not found.' }
Invoke-AwsCli @('cognito-idp','update-managed-login-branding','--user-pool-id',$ids.userPoolId,'--managed-login-branding-id',$id,'--settings',"file://$settings",'--query','ManagedLoginBranding.LastModifiedDate','--output','text') | Out-Null
Step "BRANDING DONE: $app colours applied to style $id"
Read-Host 'Press Enter to close'

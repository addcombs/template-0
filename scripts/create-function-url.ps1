# Setup step 3: gives the API's `live` alias a function URL with auth type NONE, for the API's
# CloudFront distribution to call (step 5, create-api-cloudfront). The API itself requires a verified Cognito token on /api/account. A public URL needs
# two permissions on the alias: lambda:InvokeFunctionUrl, and lambda:InvokeFunction limited to calls
# made through the URL. Safe to re-run: existing URL and permissions are kept.
# Log: logs\function-url.log
. "$PSScriptRoot\common.ps1" -LogName 'function-url.log' -Title 'function URL'
$fn = $names.Function

$url = Invoke-AwsCli @('lambda','get-function-url-config','--function-name',$fn,'--qualifier','live','--query','FunctionUrl','--output','text') -AllowFail -Quiet
if (-not $url) {
  $url = Invoke-AwsCli @('lambda','create-function-url-config','--function-name',$fn,'--qualifier','live','--auth-type','NONE','--query','FunctionUrl','--output','text')
  Step "function URL created: $url"
} else { Step "function URL exists: $url" }

$policy = Invoke-AwsCli @('lambda','get-policy','--function-name',$fn,'--qualifier','live','--query','Policy','--output','text') -AllowFail -Quiet
$sids = if ($policy) { @(($policy | ConvertFrom-Json).Statement | ForEach-Object { $_.Sid }) } else { @() }
$permissions = [ordered]@{
  FunctionURLAllowPublicAccess = @('--action','lambda:InvokeFunctionUrl','--function-url-auth-type','NONE')
  FunctionURLAllowInvokeAction = @('--action','lambda:InvokeFunction','--invoked-via-function-url')
}
foreach ($sid in $permissions.Keys) {
  if ($sids -contains $sid) { Step "permission exists: $sid"; continue }
  Invoke-AwsCli (@('lambda','add-permission','--function-name',$fn,'--qualifier','live','--statement-id',$sid,'--principal','*') + $permissions[$sid]) | Out-Null
  Step "permission added: $sid"
}
Step "DONE. Function URL for step 5 (the origin of the API's CloudFront distribution): $url"
Read-Host 'Press Enter to close'

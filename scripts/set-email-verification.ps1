# Turns the emailed verification code at sign-up off or back on.
#   -Mode Off: a pre-sign-up Lambda trigger (<app>-auto-confirm) confirms each new account and marks
#     its email verified, so registering needs no code and the account can sign in at once. The API
#     still sees a verified email in the ID token, which it requires.
#   -Mode On: removes the trigger, so Cognito emails a code again (as create-cognito-pool.ps1 set up).
# update-user-pool resets every setting it is not given, so the pool's current settings are read and
# passed back with only the trigger changed. Safe to re-run. Log: logs\email-verification.log
param([Parameter(Mandatory)][ValidateSet('On', 'Off')][string]$Mode)
. "$PSScriptRoot\common.ps1" -LogName 'email-verification.log' -Title "email verification $Mode"
$poolId = (Get-CognitoIds).userPoolId
$account = Invoke-AwsCli @('sts','get-caller-identity','--query','Account','--output','text')
$poolArn = "arn:aws:cognito-idp:${awsRegion}:${account}:userpool/$poolId"
$function = $names.SignUpTrigger

if ($Mode -eq 'Off') {
  # --- the trigger's role: only CloudWatch logging ---
  $roleName = $names.SignUpTriggerRole
  $roleArn = Invoke-AwsCli @('iam','get-role','--role-name',$roleName,'--query','Role.Arn','--output','text') -AllowFail -Quiet
  if (-not $roleArn) {
    $trust = Join-Path $logs 'auto-confirm-trust.json'
    Write-Utf8 $trust '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    $roleArn = Invoke-AwsCli @('iam','create-role','--role-name',$roleName,'--assume-role-policy-document',"file://$trust",'--query','Role.Arn','--output','text')
    Invoke-AwsCli @('iam','attach-role-policy','--role-name',$roleName,'--policy-arn','arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole') | Out-Null
    Step "role created: $roleArn (waiting 15 s for it to propagate)"
    Start-Sleep 15
  } else { Step "role exists: $roleArn" }

  # --- the trigger ---
  $src = Join-Path $logs 'auto-confirm'
  New-Item -ItemType Directory -Force $src | Out-Null
  Write-Utf8 (Join-Path $src 'index.mjs') @'
// Cognito pre-sign-up trigger: confirms the new account and marks its email verified, so no code is sent.
export const handler = async (event) => {
  event.response.autoConfirmUser = true;
  if (event.request.userAttributes.email) event.response.autoVerifyEmail = true;
  return event;
};
'@
  $zip = Join-Path $logs 'auto-confirm.zip'
  Compress-Archive -Path (Join-Path $src 'index.mjs') -DestinationPath $zip -Force
  $arn = Invoke-AwsCli @('lambda','get-function','--function-name',$function,'--query','Configuration.FunctionArn','--output','text') -AllowFail -Quiet
  if (-not $arn) {
    for ($try = 1; $try -le 4 -and -not $arn; $try++) {
      $arn = Invoke-AwsCli @('lambda','create-function','--function-name',$function,'--runtime','nodejs22.x','--architectures','arm64',
        '--role',$roleArn,'--handler','index.handler','--zip-file',"fileb://$zip",'--timeout','5',
        '--query','FunctionArn','--output','text') -AllowFail
      if (-not $arn) { Step "create-function attempt $try failed (the role may still be propagating); retrying in 10 s"; Start-Sleep 10 }
    }
    if (-not $arn) { Fail 'create-function failed 4 times; see logs\email-verification.log' }
    Step "trigger created: $arn"
  } else {
    Invoke-AwsCli @('lambda','update-function-code','--function-name',$function,'--zip-file',"fileb://$zip",'--query','LastUpdateStatus','--output','text') | Out-Null
    Step "trigger updated: $arn"
  }
  Invoke-AwsCli @('lambda','wait','function-active-v2','--function-name',$function) | Out-Null
  # Only this pool may invoke it.
  $granted = Invoke-AwsCli @('lambda','add-permission','--function-name',$function,'--statement-id','cognito-pre-sign-up',
    '--action','lambda:InvokeFunction','--principal','cognito-idp.amazonaws.com','--source-arn',$poolArn) -AllowFail -Quiet
  Step $(if ($granted) { "pool $poolId may invoke the trigger" } else { 'invoke permission already in place' })
}

# --- the pool's settings, with only the pre-sign-up trigger changed ---
$pool = Invoke-AwsCli @('cognito-idp','describe-user-pool','--user-pool-id',$poolId,'--query','UserPool','--output','json') | ConvertFrom-Json
$update = [ordered]@{ UserPoolId = $poolId }
foreach ($key in 'Policies','DeletionProtection','LambdaConfig','AutoVerifiedAttributes','SmsVerificationMessage',
  'EmailVerificationMessage','EmailVerificationSubject','VerificationMessageTemplate','SmsAuthenticationMessage',
  'UserAttributeUpdateSettings','MfaConfiguration','DeviceConfiguration','EmailConfiguration','SmsConfiguration',
  'UserPoolTags','AdminCreateUserConfig','UserPoolAddOns','AccountRecoverySetting','PoolName','UserPoolTier') {
  if ($null -ne $pool.$key) { $update[$key] = $pool.$key }
}
# Deprecated, and rejected alongside the password policy's TemporaryPasswordValidityDays.
if ($update.AdminCreateUserConfig) { $update.AdminCreateUserConfig.PSObject.Properties.Remove('UnusedAccountValidityDays') }
$lambdaConfig = [ordered]@{}
if ($pool.LambdaConfig) { foreach ($p in $pool.LambdaConfig.PSObject.Properties) { $lambdaConfig[$p.Name] = $p.Value } }
if ($Mode -eq 'Off') { $lambdaConfig['PreSignUp'] = $arn } else { $lambdaConfig.Remove('PreSignUp') }
$update['LambdaConfig'] = $lambdaConfig
$updateFile = Write-Json (Join-Path $logs 'email-verification-pool.json') $update
Invoke-AwsCli @('cognito-idp','update-user-pool','--cli-input-json',"file://$updateFile") | Out-Null

if ($Mode -eq 'Off') {
  Step "DONE. New accounts in $poolId are confirmed at sign-up without an emailed code. Undo with -Mode On."
} else {
  Step "DONE. New accounts in $poolId must enter the code emailed to them again. The $function function is left in place, unused."
}
Read-Host 'Press Enter to close'

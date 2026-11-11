# Builds, tests and deploys the API to AWS Lambda: IAM role, deploy bucket, zip
# upload, function with SnapStart and its settings, published version and the `live` alias. Safe
# to re-run: existing resources are reused and the function is updated. Pushes to main deploy new
# code (.github/workflows/ci.yml) but never the settings, so re-run this after changing .env or
# the Cognito pool.
# Secrets: settings are read from <app>-api\.env into the git-ignored lambda-env.json, and
# no AWS response that contains environment variables is printed or logged.
# Logs: logs\deploy-api.log, logs\deploy-api-build.log (the full Maven output)
. "$PSScriptRoot\common.ps1" -LogName 'deploy-api.log' -Title 'API deploy'
$function = $names.Function
$roleName = $names.Role
# Wraps the adapter's SpringDelegatingLambdaContainerHandler so response headers reach function URLs.
$handler  = "$javaPackage.lambda.FunctionUrlHandler"
$mainClass = "$javaPackage.ApiApplication"

Set-Location $apiDir
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { Fail 'AWS CLI not found on PATH.' }

# --- build the Lambda package, <app>-api\target\*-lambda.zip ---
Step 'building and testing the Lambda package...'
$buildLog = Join-Path $logs 'deploy-api-build.log'
& mvn.cmd -P lambda --batch-mode --no-transfer-progress package *>&1 | ForEach-Object { "$_" } | Set-Content $buildLog
if ($LASTEXITCODE -ne 0) { Fail "Maven build failed (exit $LASTEXITCODE); see logs\deploy-api-build.log" }
$zip = (Get-ChildItem (Join-Path $apiDir 'target\*-lambda.zip') | Sort-Object LastWriteTime | Select-Object -Last 1).FullName
Step "built $(Split-Path -Leaf $zip) ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB)"

# --- account ---
$account = Invoke-AwsCli @('sts','get-caller-identity','--query','Account','--output','text')
Step "account: $account, region: $awsRegion, profile: $profileName"

# --- settings from .env -> lambda-env.json (git-ignored) ---
$envFile = Join-Path $apiDir '.env'
if (-not (Test-Path $envFile)) { Fail ".env not found in $app-api." }
# MANAGEMENT_HEALTH_DISKSPACE_PATH: Lambda's code folder (/var/task) is read-only with 0 bytes free,
# which makes the disk-space health check report DOWN; /tmp is Lambda's writable scratch space.
# CORS_ALLOWED_ORIGINS: the UI at https://<domain> calls the API at https://api.<domain>.
# DATABASE_SCHEMA: the app's own schema in the shared database (see common.ps1).
# COGNITO_*: the app's user pool, from state\cognito-pool.json; .env supplies only the database login.
$ids = Get-CognitoIds
$vars = [ordered]@{ MAIN_CLASS = $mainClass; SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE = '2'; MANAGEMENT_HEALTH_DISKSPACE_PATH = '/tmp'
  CORS_ALLOWED_ORIGINS = "https://$domain"; DATABASE_SCHEMA = $dbSchema
  COGNITO_ISSUER = $ids.issuer; COGNITO_CLIENT_ID = $ids.userPoolClientId }
foreach ($line in Get-Content $envFile) {
  if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
  $k, $v = $line -split '=', 2
  $k = $k.Trim()
  if ($k -in @('DATABASE_URL','DATABASE_USERNAME','DATABASE_PASSWORD')) { $vars[$k] = $v.Trim().Replace('\\','\') }
}
foreach ($k in @('DATABASE_URL','DATABASE_USERNAME','DATABASE_PASSWORD')) {
  if (-not $vars.Contains($k) -or -not $vars[$k]) { Fail "$k is missing from .env." }
}
if ($vars['DATABASE_URL'] -notmatch '-pooler\.') { Step 'note: DATABASE_URL uses the direct Neon host; the pooled host (-pooler) suits Lambda better.' }
$envJson = Write-Json (Join-Path $apiDir 'lambda-env.json') @{ Variables = $vars }
Step "settings: $($vars.Keys -join ', ') (values not shown)"

# --- IAM role ---
$roleArn = Invoke-AwsCli @('iam','get-role','--role-name',$roleName,'--query','Role.Arn','--output','text') -AllowFail
if (-not $roleArn) {
  $trust = Join-Path $apiDir 'trust.json'
  Write-Utf8 $trust '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
  $roleArn = Invoke-AwsCli @('iam','create-role','--role-name',$roleName,'--assume-role-policy-document',"file://$trust",'--query','Role.Arn','--output','text')
  Invoke-AwsCli @('iam','attach-role-policy','--role-name',$roleName,'--policy-arn','arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole') | Out-Null
  Step "role created: $roleArn (waiting 15 s for it to propagate)"
  Start-Sleep 15
} else { Step "role exists: $roleArn" }

# --- deploy bucket + upload ---
$bucket = DeployBucket $account
if ($null -eq (Invoke-AwsCli @('s3api','head-bucket','--bucket',$bucket) -AllowFail -Quiet)) {
  Invoke-AwsCli @('s3api','create-bucket','--bucket',$bucket,'--create-bucket-configuration',"LocationConstraint=$awsRegion") | Out-Null
  Invoke-AwsCli @('s3api','put-public-access-block','--bucket',$bucket,'--public-access-block-configuration','BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true') | Out-Null
  Step "bucket created: $bucket (public access blocked)"
} else { Step "bucket exists: $bucket" }
$key = $names.DeployKey
Step "uploading $([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB zip..."
Invoke-AwsCli @('s3','cp',$zip,"s3://$bucket/$key",'--only-show-errors') | Out-Null
Step 'upload done'

# --- function (create or update) ---
$exists = Invoke-AwsCli @('lambda','get-function','--function-name',$function,'--query','Configuration.FunctionArn','--output','text') -AllowFail -Quiet
if (-not $exists) {
  # A new role can take a little longer to become usable by Lambda, so retry a few times.
  $createArgs = @('lambda','create-function','--function-name',$function,'--runtime','java21','--architectures','arm64',
    '--memory-size','1024','--timeout','30','--role',$roleArn,'--handler',$handler,
    '--code',"S3Bucket=$bucket,S3Key=$key",'--snap-start','ApplyOn=PublishedVersions',
    '--environment',"file://$envJson",'--query','FunctionArn','--output','text')
  $arn = $null
  for ($try = 1; $try -le 4 -and -not $arn; $try++) {
    $arn = Invoke-AwsCli $createArgs -Quiet -AllowFail
    if (-not $arn) { Step "create-function attempt $try failed; retrying in 10 s"; Start-Sleep 10 }
  }
  if (-not $arn) { Fail 'create-function failed 4 times; see logs\deploy-api.log' }
  Step "function created: $arn"
  Invoke-AwsCli @('lambda','wait','function-active-v2','--function-name',$function) | Out-Null
} else {
  Invoke-AwsCli @('lambda','update-function-code','--function-name',$function,'--s3-bucket',$bucket,'--s3-key',$key,'--query','LastUpdateStatus','--output','text') -Quiet | Out-Null
  Invoke-AwsCli @('lambda','wait','function-updated-v2','--function-name',$function) | Out-Null
  Invoke-AwsCli @('lambda','update-function-configuration','--function-name',$function,'--handler',$handler,'--environment',"file://$envJson",'--query','LastUpdateStatus','--output','text') -Quiet | Out-Null
  Invoke-AwsCli @('lambda','wait','function-updated-v2','--function-name',$function) | Out-Null
  Step "function updated: $exists"
}

# --- publish version (SnapStart snapshot) + live alias ---
Step 'publishing a version; SnapStart takes the snapshot now (a few minutes)...'
$version = Invoke-AwsCli @('lambda','publish-version','--function-name',$function,'--query','Version','--output','text') -Quiet
if ($null -eq (Invoke-AwsCli @('lambda','wait','published-version-active','--function-name',$function,'--qualifier',$version) -AllowFail)) {
  for ($i = 0; $i -lt 60; $i++) {
    $fnState = Invoke-AwsCli @('lambda','get-function-configuration','--function-name',$function,'--qualifier',$version,'--query','State','--output','text') -Quiet
    if ($fnState -ne 'Pending') { break }
    Start-Sleep 10
  }
}
$snap = Invoke-AwsCli @('lambda','get-function-configuration','--function-name',$function,'--qualifier',$version,'--query','[State, SnapStart.OptimizationStatus]','--output','text') -Quiet
Step "version $version published (state, SnapStart: $snap)"
$alias = Invoke-AwsCli @('lambda','get-alias','--function-name',$function,'--name','live','--query','AliasArn','--output','text') -AllowFail -Quiet
if (-not $alias) {
  $alias = Invoke-AwsCli @('lambda','create-alias','--function-name',$function,'--name','live','--function-version',$version,'--query','AliasArn','--output','text')
} else {
  $alias = Invoke-AwsCli @('lambda','update-alias','--function-name',$function,'--name','live','--function-version',$version,'--query','AliasArn','--output','text')
}
Step "alias live -> version ${version}: $alias"
Step 'DONE. On a first deploy, next run scripts\create-function-url.ps1 (step 3).'
Read-Host 'Press Enter to close'

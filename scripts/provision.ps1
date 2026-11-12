# Sets up, or updates, everything the app runs on, in one go (README.md, Create a new app):
#  1. the GitHub repository (created from this folder and pushed if git has no origin yet)
#  2. the shared certificate for the apex and *.apex (requested by the first app that needs it)
#  3. the CDK stack in infra\: Cognito sign-in, buckets, the API on Lambda, one CloudFront
#     distribution for the UI and the API, its Route 53 records, and the GitHub deploy role
#  4. config\cognito-pool.json and the UI's settings from the stack, and the sign-in page's style
#  5. the database schema and migrations
#  6. the repository's AWS_DEPLOY_ROLE_ARN variable, then a push or a CI run to deploy the UI and API
# Safe to re-run; run it again after changing project.json, the infra code or the API's .env (the
# database login reaches the function only from here, never from GitHub).
#   -Visibility private   for a new repository (default public)
#   -SkipDeploy           stops before step 6
#   -ImportExisting       one-off, for an app first set up by the old scripts: adopts its user pool,
#                         client, sign-in domain, buckets, roles and functions into the new stack
#                         (users and files stay), then moves its host to the new distribution
#                         (down 5-15 minutes); afterwards scripts\remove-old-setup.ps1 cleans up
# Log: logs\provision.log (cdk output in logs\cdk-deploy.log)
param([ValidateSet('public', 'private')][string]$Visibility = 'public', [switch]$SkipDeploy, [switch]$ImportExisting)
. "$PSScriptRoot\common.ps1" -LogName 'provision.log' -Title 'provision'
$env:SETUP_NO_PAUSE = '1'
$infra = Join-Path $root 'infra'
foreach ($tool in 'aws.exe', 'node.exe', 'java.exe', 'mvn.cmd', 'git.exe') {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { Fail "$tool not found on PATH." }
}
if (-not $gh) { Fail 'GitHub CLI (gh) not found; install it and run gh auth login.' }
$account = Invoke-AwsCli @('sts','get-caller-identity','--query','Account','--output','text')
Step "account: $account, region: $awsRegion, profile: $profileName"

# --- 1. GitHub repository ---
$origin = & git -C $root remote get-url origin 2>$null
if (-not $origin) {
  $owner = & $gh api user --jq .login
  Step "creating the $Visibility repository $owner/$app and pushing..."
  & $gh repo create "$owner/$app" "--$Visibility" --source $root --remote origin --push 2>&1 | ForEach-Object { Step "$_" }
  if ($LASTEXITCODE -ne 0) { Fail 'gh repo create failed. If the push was refused for lack of the workflow scope, run: gh auth refresh -h github.com -s workflow' }
  $origin = & git -C $root remote get-url origin
}
if ($origin -notmatch 'github\.com[:/]([^/]+/[^/]+?)(\.git)?$') { Fail "git origin '$origin' is not a GitHub repository." }
$repo = $Matches[1]
# GitHub's tokens name the repository with its owner's and its own IDs, so the deploy role's trust
# policy must too: repo:<owner>@<owner id>/<repo>@<repo id>:ref:refs/heads/main.
$info = & $gh api "repos/$repo" | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { Fail "could not look up $repo on GitHub." }
$subject = "repo:$($info.owner.login)@$($info.owner.id)/$($info.name)@$($info.id):ref:refs/heads/main"
Step "repository: $repo"

# GitHub's OIDC provider, one per account and shared by every app's deploy role.
$providerHost = 'token.actions.githubusercontent.com'
$provider = "arn:aws:iam::${account}:oidc-provider/$providerHost"
if ($null -eq (Invoke-AwsCli @('iam','get-open-id-connect-provider','--open-id-connect-provider-arn',$provider) -AllowFail -Quiet)) {
  Invoke-AwsCli @('iam','create-open-id-connect-provider','--url',"https://$providerHost",'--client-id-list','sts.amazonaws.com') | Out-Null
  Step "OIDC provider created: $provider"
}

# --- 2. shared certificate ---
$certArn = Get-SharedCertificate
$zoneId = Get-HostedZoneId

# --- 3. the stack ---
# The function's first code comes from this build; after that each push to main deploys new code.
Step 'building and testing the API''s Lambda package...'
$buildLog = Join-Path $logs 'provision-api-build.log'
Push-Location $apiDir
& mvn.cmd -P lambda --batch-mode --no-transfer-progress package *>&1 | ForEach-Object { "$_" } | Set-Content $buildLog
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { Fail "Maven build failed (exit $code); see logs\provision-api-build.log" }

$envFile = Join-Path $apiDir '.env'
if (-not (Test-Path $envFile)) { Fail ".env not found in $app-api." }
$db = @{}
foreach ($line in Get-Content $envFile) {
  if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
  $k, $v = $line -split '=', 2
  $db[$k.Trim()] = $v.Trim().Replace('\\', '\')
}
foreach ($k in 'DATABASE_URL', 'DATABASE_USERNAME', 'DATABASE_PASSWORD') { if (-not $db[$k]) { Fail "$k is missing from .env." } }
if ($db.DATABASE_URL -notmatch '-pooler\.') { Step 'note: DATABASE_URL uses the direct Neon host; the pooled host (-pooler) suits Lambda better.' }

Push-Location $infra
if (-not (Test-Path 'node_modules')) {
  Step 'installing the CDK (npm ci in infra\)...'
  Invoke-Npm @('ci', '--no-audit', '--no-fund') *>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { Pop-Location; Fail 'npm ci failed in infra\.' }
}
$cdk = @('exec', '--', 'cdk')
$cdkArgs = @('--profile', $profileName, '-c', "certificateArn=$certArn", '-c', "hostedZoneId=$zoneId", '-c', "githubSubject=$subject")
$deployLog = Join-Path $logs 'cdk-deploy.log'
# CDK keeps its deploy assets in a bootstrap stack, one per account and region.
if ($null -eq (Invoke-AwsCli @('cloudformation','describe-stacks','--stack-name','CDKToolkit') -AllowFail -Quiet)) {
  Step "bootstrapping the CDK in $awsRegion (once per account and region)..."
  Invoke-Npm @($cdk + @('bootstrap', "aws://$account/$awsRegion") + $cdkArgs) *>&1 | ForEach-Object { "$_" } | Set-Content $deployLog
  if ($LASTEXITCODE -ne 0) { Pop-Location; Fail 'cdk bootstrap failed; see logs\cdk-deploy.log' }
}
if ($ImportExisting -and $null -eq (Invoke-AwsCli @('cloudformation','describe-stacks','--stack-name',$app) -AllowFail -Quiet)) {
  # --- one-off: adopt what the old setup scripts made, then free the host for the new distribution ---
  $poolId = Invoke-AwsCli @('cognito-idp','list-user-pools','--max-results','60','--query',"UserPools[?Name=='$app-users'].Id | [0]",'--output','text')
  if (-not $poolId -or $poolId -eq 'None') { Pop-Location; Fail "no user pool named $app-users to import." }
  $clientId = Invoke-AwsCli @('cognito-idp','list-user-pool-clients','--user-pool-id',$poolId,'--query',"UserPoolClients[?ClientName=='$app-ui'].ClientId | [0]",'--output','text')
  $fnArn = Invoke-AwsCli @('lambda','get-function','--function-name',"$app-api",'--query','Configuration.FunctionArn','--output','text')
  # Each resource the import-only template has, by its construct path, and how CloudFormation finds it.
  $ids = [ordered]@{
    'Users' = @{ UserPoolId = $poolId }
    'Users/Ui' = @{ UserPoolId = $poolId; ClientId = $clientId }
    'Users/SignIn' = @{ UserPoolId = $poolId; Domain = $project.cognito.domainPrefix }
    'UiBucket' = @{ BucketName = "$app-ui-$account" }
    'DeployBucket' = @{ BucketName = "$app-deploy-$account" }
    'ApiRole' = @{ RoleName = "$app-api-lambda" }
    'Api' = @{ FunctionName = "$app-api" }
    'Live' = @{ AliasArn = "${fnArn}:live" }
    'LiveUrl' = @{ FunctionArn = "${fnArn}:live" }
    'GitHubDeploy' = @{ RoleName = "$app-github-deploy" }
    'AutoConfirm' = @{ FunctionName = "$app-auto-confirm" }
    'AutoConfirmRole' = @{ RoleName = "$app-auto-confirm-lambda" }
  }
  $importOut = Join-Path $infra 'cdk.out.import'
  Invoke-Npm @($cdk + @('synth', '-q', '-o', $importOut, '-c', 'importOnly=true') + $cdkArgs) *>&1 | ForEach-Object { "$_" } | Set-Content $deployLog
  if ($LASTEXITCODE -ne 0) { Pop-Location; Fail 'cdk synth (import) failed; see logs\cdk-deploy.log' }
  $template = Get-Content (Join-Path $importOut "$app.template.json") -Raw | ConvertFrom-Json
  $mapping = [ordered]@{}
  foreach ($r in $template.Resources.PSObject.Properties) {
    $path = $r.Value.Metadata.'aws:cdk:path'
    if (-not $path) { continue }
    $key = ($path -replace "^$([regex]::Escape($app))/", '') -replace '/Resource$', ''
    if (-not $ids.Contains($key)) { Pop-Location; Fail "no identifier for $path in the import template." }
    $mapping[$r.Name] = $ids[$key]
  }
  $mappingFile = Write-Json (Join-Path $logs 'cdk-import-mapping.json') $mapping
  Step "importing $($mapping.Count) existing resources into the $app stack (user pool $poolId)..."
  Invoke-Npm @($cdk + @('import', '--resource-mapping', $mappingFile, '--force', '-c', 'importOnly=true') + $cdkArgs) *>&1 |
    ForEach-Object { "$_" } | Add-Content $deployLog
  if ($LASTEXITCODE -ne 0) { Pop-Location; Fail 'cdk import failed; see logs\cdk-deploy.log' }
  Remove-Item $importOut -Recurse -Force
  Step 'imported'

  # The old UI distribution keeps working without its alias until remove-old-setup.ps1 deletes it; the
  # host is down from here until the new distribution is deployed (5-15 minutes).
  $oldId = Invoke-AwsCli @('cloudfront','list-distributions','--query',"DistributionList.Items[?Aliases.Items && contains(Aliases.Items, '$domain')].Id | [0]",'--output','text')
  if ($oldId -and $oldId -ne 'None') {
    $current = Invoke-AwsCli @('cloudfront','get-distribution-config','--id',$oldId,'--output','json') | ConvertFrom-Json
    $current.DistributionConfig.Aliases = [ordered]@{ Quantity = 0 }
    $configFile = Write-Json (Join-Path $logs 'old-distribution-config.json') $current.DistributionConfig
    Invoke-AwsCli @('cloudfront','update-distribution','--id',$oldId,'--if-match',$current.ETag,'--distribution-config',"file://$configFile",'--query','Distribution.Status','--output','text') | Out-Null
    Step "old distribution $oldId no longer answers for $domain"
  }
  $zoneRecords = Invoke-AwsCli @('route53','list-resource-record-sets','--hosted-zone-id',$zoneId,'--start-record-name',"$domain.",'--output','json') | ConvertFrom-Json
  $old = @($zoneRecords.ResourceRecordSets | Where-Object { $_.Name -eq "$domain." -and $_.Type -in 'A', 'AAAA', 'CNAME' })
  if ($old) {
    $batch = Write-Json (Join-Path $logs 'dns-change.json') @{ Changes = @($old | ForEach-Object { @{ Action = 'DELETE'; ResourceRecordSet = $_ } }) }
    Invoke-AwsCli @('route53','change-resource-record-sets','--hosted-zone-id',$zoneId,'--change-batch',"file://$batch") | Out-Null
    Step "old DNS records for $domain removed ($(($old.Type) -join ', '))"
  }
}
Step 'deploying the stack (a new CloudFront distribution takes 5-15 minutes)...'
$outputs = Join-Path $logs 'cdk-outputs.json'
# The output is not shown: CDK echoes parameter values, and these are the database login.
$params = @('--parameters', "DatabaseUrl=$($db.DATABASE_URL)", '--parameters', "DatabaseUsername=$($db.DATABASE_USERNAME)", '--parameters', "DatabasePassword=$($db.DATABASE_PASSWORD)")
Invoke-Npm @($cdk + @('deploy', '--require-approval', 'never', '--outputs-file', $outputs) + $cdkArgs + $params) *>&1 |
  ForEach-Object { "$_" } | Where-Object { $_ -notmatch 'Database(Url|Username|Password)' } | Set-Content $deployLog
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { Fail "cdk deploy failed (exit $code); see logs\cdk-deploy.log" }
$out = (Get-Content $outputs -Raw | ConvertFrom-Json).$app
Step "stack deployed: distribution $($out.DistributionId), user pool $($out.UserPoolId)"

# --- 4. Cognito IDs, UI settings, theme palettes and the sign-in page's style ---
Write-Json $cognitoPoolFile ([ordered]@{
  userPoolId = $out.UserPoolId; userPoolClientId = $out.UserPoolClientId; domain = $out.SignInDomain; issuer = $out.Issuer
}) | Out-Null
Sync-UiConfig
if (-not (Test-Path (Join-Path $uiDir 'node_modules\.bin\ng.cmd'))) {
  Step 'installing the UI''s packages (npm ci)...'
  Push-Location $uiDir
  Invoke-Npm @('ci', '--no-audit', '--no-fund') *>&1 | Out-Null
  $code = $LASTEXITCODE
  Pop-Location
  if ($code -ne 0) { Fail "npm ci failed in $app-ui." }
}
try { Sync-Theme } catch { Fail $_.Exception.Message }
# CI applies the theme colors to this style on each deploy; Cognito's default starts it off.
$brandingId = Invoke-AwsCli @('cognito-idp','describe-managed-login-branding-by-client','--user-pool-id',$out.UserPoolId,'--client-id',$out.UserPoolClientId,
  '--query','ManagedLoginBranding.ManagedLoginBrandingId','--output','text') -AllowFail -Quiet
if (-not $brandingId -or $brandingId -eq 'None') {
  Invoke-AwsCli @('cognito-idp','create-managed-login-branding','--user-pool-id',$out.UserPoolId,'--client-id',$out.UserPoolClientId,
    '--use-cognito-provided-values','--query','ManagedLoginBranding.ManagedLoginBrandingId','--output','text') | Out-Null
  Step 'sign-in page style created (Cognito''s default; the first deploy applies the theme colors)'
}

# --- 5. database ---
& "$PSScriptRoot\apply-migrations.ps1"
if ($LASTEXITCODE -ne 0) { Fail 'migrations failed; see logs\migrations.log' }

if ($SkipDeploy) { Step "DONE (no deploy). https://$domain/ serves the UI after the next deploy from main."; Wait-Close; exit 0 }

# --- 6. deploy ---
& $gh variable set AWS_DEPLOY_ROLE_ARN --repo $repo --body $out.DeployRoleArn
if ($LASTEXITCODE -ne 0) { Fail 'could not set the AWS_DEPLOY_ROLE_ARN variable.' }
Step "AWS_DEPLOY_ROLE_ARN = $($out.DeployRoleArn)"
# A push of new settings or palettes deploys by itself; otherwise start the workflow.
$generated = @("$app-ui/src/app/project.settings.ts", "$app-ui/src/app/theme/generated_theme-colors.scss")
& git -C $root add -- @generated
& git -C $root diff --cached --quiet -- @generated
if ($LASTEXITCODE -ne 0) {
  & git -C $root commit -q -m 'Point the UI at the provisioned sign-in and theme' -- @generated
  & git -C $root push -q origin HEAD:main
  if ($LASTEXITCODE -ne 0) { Fail 'git push failed.' }
  Step 'UI settings committed and pushed; the push deploys'
  $runFilter = @('--event', 'push', '--commit', (& git -C $root rev-parse HEAD))
} else {
  & $gh workflow run ci.yml --repo $repo --ref main
  if ($LASTEXITCODE -ne 0) { Fail 'could not start the CI workflow.' }
  $runFilter = @('--event', 'workflow_dispatch')
}
$runId = $null
for ($i = 0; $i -lt 12 -and -not $runId; $i++) {
  Start-Sleep 5
  $runId = & $gh run list --repo $repo --workflow ci.yml --branch main @runFilter --limit 1 --json databaseId --jq '.[0].databaseId'
}
if (-not $runId) { Fail "the CI run did not start; see https://github.com/$repo/actions" }
Step "waiting for CI run $runId (build, tests and deploy, about 5-10 minutes)..."
& $gh run watch $runId --repo $repo --exit-status *>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "CI run $runId failed: https://github.com/$repo/actions/runs/$runId" }
Step "DONE. https://$domain/ is live."
Wait-Close

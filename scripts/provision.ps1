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
# Log: logs\provision.log (cdk output in logs\cdk-deploy.log)
param([ValidateSet('public', 'private')][string]$Visibility = 'public', [switch]$SkipDeploy)
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

# --- 4. Cognito IDs, UI settings and the sign-in page's style ---
Write-Json $cognitoPoolFile ([ordered]@{
  userPoolId = $out.UserPoolId; userPoolClientId = $out.UserPoolClientId; domain = $out.SignInDomain; issuer = $out.Issuer
}) | Out-Null
Sync-UiConfig
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
# A push of the new settings deploys by itself; otherwise start the workflow.
$settings = "$app-ui/src/app/project.settings.ts"
& git -C $root add -- $settings
& git -C $root diff --cached --quiet -- $settings
if ($LASTEXITCODE -ne 0) {
  & git -C $root commit -q -m 'Point the UI at the provisioned sign-in' -- $settings
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

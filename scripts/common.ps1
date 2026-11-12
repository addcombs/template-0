# Shared setup for the scripts in this folder. Dot-source it first, e.g.
#   . "$PSScriptRoot\common.ps1" -LogName 'cloudfront.log' -Title 'CloudFront'
# Loads ..\project.json (the only per-app settings) and derives every AWS resource name from the app
# name, so a new app needs only its own project.json. Folders under the project root:
#   logs\    run logs and generated request files (git-ignored)
#   config\  hand-maintained inputs, e.g. managed-login-branding.json, and cognito-pool.json, the
#            Cognito IDs AWS assigned (written by create-cognito-pool.ps1, git-ignored)
# Native tools write normal output to stderr; Windows PowerShell 5 would treat that as a terminating
# error under 'Stop', so failures are checked via exit codes.
param([string]$LogName, [string]$Title, [switch]$AppendLog)
$ErrorActionPreference = 'Continue'
$root   = Split-Path -Parent $PSScriptRoot
$logs   = Join-Path $root 'logs'
$config = Join-Path $root 'config'
New-Item -ItemType Directory -Force $logs | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

$project     = Get-Content (Join-Path $root 'project.json') -Raw | ConvertFrom-Json
$app         = $project.name
$profileName = $project.aws.profile
$awsRegion   = $project.aws.region
$domain      = $project.domain.host
$apex        = $project.domain.apex
# The API has its own CloudFront distribution at api.<host>, e.g. api.template-0.acombs-dev.com.
$apiDomain    = "api.$domain"
# ACM certificates used by CloudFront must be in us-east-1, whatever the app's region.
$cloudFrontRegion = 'us-east-1'
# The app's schema in the shared database: project.json database.schema, or else the app name in
# lower case with other characters as underscores (project-1 -> project_1).
$dbSchema = if ($project.database.schema) { $project.database.schema } else { ($app -replace '[^A-Za-z0-9]', '_').ToLowerInvariant() }
# The API's Java package: com.acombsdev.<app name in lower-case letters and digits>, e.g. com.acombsdev.template0.
$javaPackage = 'com.acombsdev.' + ($app -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
$apiDir = Join-Path $root "$app-api"
$uiDir  = Join-Path $root "$app-ui"
$names = [ordered]@{
  Function     = "$app-api"
  Role         = "$app-api-lambda"
  DeployKey    = "$app-api-lambda.zip"
  GitHubDeployRole = "$app-github-deploy"
  UserPool     = "$app-users"
  UserClient   = "$app-ui"
  SignUpTrigger     = "$app-auto-confirm"
  SignUpTriggerRole = "$app-auto-confirm-lambda"
  Oac          = "$app-ui-oac"
  # ACM idempotency tokens allow only letters and digits.
  CertToken    = (($app -replace '[^A-Za-z0-9]', '') + 'cert')
  ApiCertToken = (($app -replace '[^A-Za-z0-9]', '') + 'apicert')
}
# Buckets include the account ID because S3 bucket names are global.
function UiBucket($account) { "$app-ui-$account" }
function DeployBucket($account) { "$app-deploy-$account" }

$log = Join-Path $logs $LogName
if (-not $AppendLog) { Set-Content $log "$app $Title $(Get-Date -Format s)" }

function Step($msg) { $line = "$(Get-Date -Format HH:mm:ss) $msg"; Write-Host $line -ForegroundColor Cyan; Add-Content $log $line }
function Fail($msg) { Step "FAILED: $msg"; Write-Host "`nFailed: $msg" -ForegroundColor Red; Read-Host 'Press Enter to close'; exit 1 }
# Runs the AWS CLI with the project's profile; returns its output text, or $null after an allowed
# failure. -Quiet keeps output out of the log (for responses that can contain secrets); a failure is
# still logged unless it was allowed.
function Invoke-AwsCli([string[]]$argv, [string]$Region = $awsRegion, [switch]$AllowFail, [switch]$Quiet) {
  $out = & aws.exe @argv --profile $profileName --region $Region 2>&1 | Out-String
  $code = $LASTEXITCODE
  if (-not $Quiet -or ($code -ne 0 -and -not $AllowFail)) { Add-Content $log $out.Trim() }
  if ($code -ne 0 -and -not $AllowFail) { Fail "aws $($argv[0]) $($argv[1]) (exit $code)" }
  if ($code -ne 0) { return $null }
  return $out.Trim()
}
function Write-Utf8($path, $text) { [System.IO.File]::WriteAllText($path, $text, $utf8) }
function Write-Json($path, $obj) { Write-Utf8 $path ($obj | ConvertTo-Json -Depth 20); return $path }

# The apex's DNS is hosted in Route 53; the scripts write their records there themselves.
# Z2FDTNDATAQYW2 is the fixed hosted zone ID AWS uses for every alias to a CloudFront distribution.
$cloudFrontZoneId = 'Z2FDTNDATAQYW2'
function Get-HostedZoneId {
  $id = Invoke-AwsCli @('route53','list-hosted-zones-by-name','--dns-name',$apex,'--query',("HostedZones[?Name=='$apex.' && Config.PrivateZone==" + '`false`' + '].Id | [0]'),'--output','text')
  if (-not $id -or $id -eq 'None') { Fail "No public Route 53 hosted zone for $apex." }
  return $id -replace '^/hostedzone/', ''
}
# Creates or replaces Route 53 record sets (each a ResourceRecordSet hashtable) in the apex's zone
# and waits until Route 53 serves them.
function Set-DnsRecords([string]$Comment, [object[]]$RecordSets) {
  $zoneId = Get-HostedZoneId
  $batch = [ordered]@{ Comment = $Comment; Changes = @($RecordSets | ForEach-Object { @{ Action = 'UPSERT'; ResourceRecordSet = $_ } }) }
  $file = Write-Json (Join-Path $logs 'dns-change.json') $batch
  $changeId = Invoke-AwsCli @('route53','change-resource-record-sets','--hosted-zone-id',$zoneId,'--change-batch',"file://$file",'--query','ChangeInfo.Id','--output','text')
  Invoke-AwsCli @('route53','wait','resource-record-sets-changed','--id',$changeId) | Out-Null
  foreach ($r in $RecordSets) { Step "Route 53 record set: $($r.Name) $($r.Type)" }
}
# Points a host at a CloudFront distribution with alias A and AAAA records (which, unlike a CNAME,
# also work at the apex).
function Set-CloudFrontAlias([string]$HostName, [string]$DistDomain) {
  $records = @('A','AAAA') | ForEach-Object {
    [ordered]@{ Name = "$HostName."; Type = $_; AliasTarget = [ordered]@{ HostedZoneId = $cloudFrontZoneId; DNSName = "$DistDomain."; EvaluateTargetHealth = $false } }
  }
  Set-DnsRecords "$HostName -> CloudFront" $records
}


# Runs the npm that ships with the Node.js on PATH (its node_modules\npm\bin\npm-cli.js). Node's
# npm.cmd hands over to a globally installed npm when there is one (e.g. an old one in %APPDATA%\npm),
# which can fail on lock files written by a newer npm. Pass npm's arguments as an array, e.g.
# Invoke-Npm @('test', '--', '--watch=false'): PowerShell drops a literal -- typed after a function.
$nodeExe = (Get-Command node.exe -ErrorAction SilentlyContinue).Source
$npmCli = if ($nodeExe) { Join-Path (Split-Path -Parent $nodeExe) 'node_modules\npm\bin\npm-cli.js' }
if ($npmCli -and -not (Test-Path $npmCli)) { $npmCli = $null }
function Invoke-Npm { if ($npmCli) { & $nodeExe $npmCli @args } else { & npm.cmd @args } }
# The same, as a command line for a new PowerShell window.
$npmCommand = if ($npmCli) { "& '$nodeExe' '$npmCli'" } else { '& npm.cmd' }

$cognitoPoolFile = Join-Path $config 'cognito-pool.json'
function Get-CognitoIds {
  if (-not (Test-Path $cognitoPoolFile)) { Fail "config\cognito-pool.json not found. Run scripts\create-cognito-pool.ps1 first." }
  return Get-Content $cognitoPoolFile -Raw | ConvertFrom-Json
}

# Writes the UI's src\app\project.settings.ts from project.json and config\cognito-pool.json. Without
# that file the IDs are left empty and the UI reports sign-in as not configured.
function Sync-UiConfig {
  $ids = if (Test-Path $cognitoPoolFile) { Get-Content $cognitoPoolFile -Raw | ConvertFrom-Json } else { $null }
  function Ts($s) { "'" + ("$s" -replace '\\', '\\' -replace "'", "\'") + "'" }
  $urls = "[$(Ts 'http://localhost:4200/'), $(Ts "https://$domain/")]"
  $text = @(
    "// Generated from project.json and config\cognito-pool.json by Sync-UiConfig in scripts\common.ps1,",
    '// which start-all runs before building. Edit those files, not this one.',
    'export const PROJECT_SETTINGS = {',
    "  appName: $(Ts $app),",
    "  displayName: $(Ts $project.displayName),",
    "  developerName: $(Ts $project.developerName),",
    "  apiUrl: $(Ts "https://$apiDomain"),",
    '  auth: {',
    "    userPoolId: $(Ts $ids.userPoolId),",
    "    userPoolClientId: $(Ts $ids.userPoolClientId),",
    "    domain: $(Ts $ids.domain),",
    "    redirectSignIn: $urls,",
    "    redirectSignOut: $urls,",
    '  },',
    '};',
    ''
  ) -join "`n"
  $file = Join-Path $uiDir 'src\app\project.settings.ts'
  $current = if (Test-Path $file) { [System.IO.File]::ReadAllText($file) } else { $null }
  if ($current -ne $text) { Write-Utf8 $file $text; Step 'UI settings written: src\app\project.settings.ts' }
  if (-not $ids) { Step 'note: config\cognito-pool.json not found; the UI will report sign-in as not configured' }
}

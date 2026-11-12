# Shared setup for the scripts in this folder. Dot-source it first, e.g.
#   . "$PSScriptRoot\common.ps1" -LogName 'migrations.log' -Title 'database migrations'
# Loads ..\project.json (the only per-app settings; infra\ derives every AWS resource name from it
# too), so a new app needs only its own project.json. Folders under the project root:
#   logs\    run logs and generated request files (git-ignored)
#   config\  hand-maintained inputs, e.g. managed-login-branding.json, and cognito-pool.json, the
#            Cognito IDs AWS assigned (written by provision.ps1, git-ignored)
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
# ACM certificates used by CloudFront must be in us-east-1, whatever the app's region.
$cloudFrontRegion = 'us-east-1'
# The app's schema in the shared database: project.json database.schema, or else the app name in
# lower case with other characters as underscores (project-1 -> project_1).
$dbSchema = if ($project.database.schema) { $project.database.schema } else { ($app -replace '[^A-Za-z0-9]', '_').ToLowerInvariant() }
# The API's Java package: com.acombsdev.<app name in lower-case letters and digits>, e.g. com.acombsdev.template0.
$javaPackage = 'com.acombsdev.' + ($app -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
$apiDir = Join-Path $root "$app-api"
$uiDir  = Join-Path $root "$app-ui"

$log = Join-Path $logs $LogName
if (-not $AppendLog) { Set-Content $log "$app $Title $(Get-Date -Format s)" }

function Step($msg) { $line = "$(Get-Date -Format HH:mm:ss) $msg"; Write-Host $line -ForegroundColor Cyan; Add-Content $log $line }
# Keeps a script's window open at the end, unless provision.ps1 is running it.
function Wait-Close { if (-not $env:SETUP_NO_PAUSE) { Read-Host 'Press Enter to close' | Out-Null } }
function Fail($msg) { Step "FAILED: $msg"; Write-Host "`nFailed: $msg" -ForegroundColor Red; Wait-Close; exit 1 }
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

# The apex's DNS is hosted in Route 53; the CDK stack writes each app's alias records, and these
# helpers the shared certificate's validation record.
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

# The certificate for the apex and *.apex that every app's distribution shares, in us-east-1. The
# first app set up requests it; its validation CNAME (one for both names) goes to Route 53, and it
# stays there so ACM can renew the certificate. Returns the certificate's ARN once it is issued.
function Get-SharedCertificate {
  $wildcard = "*.$apex"
  $arn = Invoke-AwsCli @('acm','list-certificates','--certificate-statuses','ISSUED','PENDING_VALIDATION','--query',
    "CertificateSummaryList[?DomainName=='$apex' && contains(SubjectAlternativeNameSummaries, '$wildcard')].CertificateArn | [0]",'--output','text') -Region $cloudFrontRegion
  if (-not $arn -or $arn -eq 'None') {
    # ACM idempotency tokens allow only letters and digits.
    $token = ($apex -replace '[^A-Za-z0-9]', '') + 'shared'
    $arn = Invoke-AwsCli @('acm','request-certificate','--domain-name',$apex,'--subject-alternative-names',$wildcard,'--validation-method','DNS',
      '--idempotency-token',$token,'--query','CertificateArn','--output','text') -Region $cloudFrontRegion
    Step "shared certificate requested for $apex and ${wildcard}: $arn"
  }
  $status = Invoke-AwsCli @('acm','describe-certificate','--certificate-arn',$arn,'--query','Certificate.Status','--output','text') -Region $cloudFrontRegion
  if ($status -ne 'ISSUED') {
    # ACM needs a few seconds to generate the validation record.
    $record = $null
    for ($i = 0; $i -lt 12 -and -not $record; $i++) {
      $rec = Invoke-AwsCli @('acm','describe-certificate','--certificate-arn',$arn,'--query',
        'Certificate.DomainValidationOptions[0].ResourceRecord.[Name, Value]','--output','text') -Region $cloudFrontRegion
      $name, $value = $rec -split '\s+'
      if ($name -and $name -ne 'None') { $record = [ordered]@{ Name = $name; Type = 'CNAME'; TTL = 300; ResourceRecords = @(@{ Value = $value }) } } else { Start-Sleep 5 }
    }
    if (-not $record) { Fail 'ACM did not return the shared certificate''s validation record; run this again in a minute.' }
    Set-DnsRecords "$apex shared certificate validation" @($record)
    Step 'waiting for the shared certificate to be issued (usually a few minutes)...'
    Invoke-AwsCli @('acm','wait','certificate-validated','--certificate-arn',$arn) -Region $cloudFrontRegion -AllowFail | Out-Null
    $status = Invoke-AwsCli @('acm','describe-certificate','--certificate-arn',$arn,'--query','Certificate.Status','--output','text') -Region $cloudFrontRegion
    if ($status -ne 'ISSUED') { Fail "The shared certificate is $status. Run this again later." }
  }
  Step "shared certificate: $arn"
  return $arn
}

# The GitHub CLI: on PATH, or where its installer puts it.
$gh = (Get-Command gh.exe -ErrorAction SilentlyContinue).Source
if (-not $gh -and (Test-Path "$env:ProgramFiles\GitHub CLI\gh.exe")) { $gh = "$env:ProgramFiles\GitHub CLI\gh.exe" }


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
  if (-not (Test-Path $cognitoPoolFile)) { Fail "config\cognito-pool.json not found. Run scripts\provision.ps1 first." }
  return Get-Content $cognitoPoolFile -Raw | ConvertFrom-Json
}

# Regenerates the UI's theme palettes (src\app\theme\generated_theme-colors.scss, which CI checks)
# when project.json's colour differs from the one they came from; needs the UI's node_modules. The
# whole line must match, as palettes from an older primary-and-secondary pair start the same way.
# Throws on failure. Log: logs\ui-theme.log
$themeFile = Join-Path $uiDir 'src\app\theme\generated_theme-colors.scss'
function Sync-Theme {
  $primary = $project.theme.primary
  if (-not (Select-String -Path $themeFile -Pattern "generated from primary: $([regex]::Escape($primary))\s*$" -Quiet)) {
    # The schematic writes <directory>_theme-colors.scss, i.e. src/app/theme/_generated_theme-colors.scss.
    Push-Location $uiDir
    & (Join-Path $uiDir 'node_modules\.bin\ng.cmd') generate '@angular/material:theme-color' "--primary-color=$primary" `
      '--directory=src/app/theme/_generated' '--is-scss' '--interactive=false' *>&1 | ForEach-Object { "$_" } | Set-Content (Join-Path $logs 'ui-theme.log')
    $code = $LASTEXITCODE
    Pop-Location
    $gen = Join-Path $uiDir 'src\app\theme\_generated_theme-colors.scss'
    if ($code -ne 0 -or -not (Test-Path $gen)) { throw "theme generator failed (exit $code); see logs\ui-theme.log" }
    Copy-Item $gen $themeFile -Force -ErrorAction Stop
    Remove-Item $gen -Force
    Step "theme: generated from primary $primary"
  }
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

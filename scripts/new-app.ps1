# Creates a new app from this one: copies the project to a sibling folder (..\<name>) and renames
# everything that carries the app's name, so the new app's scripts create its own AWS resources.
#  - folders <app>-api and <app>-ui, and the Java package com.acombsdev.<app> (folders and code)
#  - the app name, display name (e.g. Template 0), host, Cognito domain prefix and database schema
#    in code, tests, build files and READMEs
#  - the theme colours in the cards and README (start-all regenerates the palettes from project.json)
#  - project.json (name, host, Cognito prefix, colours); the UI settings lose this app's Cognito
#    IDs (create-cognito-pool writes the new ones)
# Copies the files git tracks or would track (no logs, state, node_modules, target or build output),
# plus the database login from <app>-api\.env, as the apps share one database. Then starts a git
# repository with one commit (skip with -NoGit). Prompts for the name when not given.
# Log: logs\new-app.log
#   scripts\new-app.ps1 -Name project-1 [-HostName project-1.acombs-dev.com] [-Primary '#RRGGBB']
#     [-CognitoPrefix project-1-acombs] [-Destination <folder>] [-NoGit]
param(
  [string]$Name, [string]$HostName, [string]$Primary,
  [string]$CognitoPrefix, [string]$Destination, [switch]$NoGit
)
. "$PSScriptRoot\common.ps1" -LogName 'new-app.log' -Title 'new app'

# The same rule as formatDisplayName in the UI's app-name.ts: template-0 -> Template 0.
function DisplayName($s) {
  (($s -replace '[^\p{L}\p{N}\s]', ' ') -split '\s+' | Where-Object { $_ } |
    ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }) -join ' '
}
# Replaces every key of $map found in $text in one pass, so a new value is never replaced again.
# With -IgnoreCase the keys must be upper case.
function Replace-All($text, $map, [switch]$IgnoreCase) {
  if (-not $map.Count) { return $text }
  $pattern = ($map.Keys | Sort-Object Length -Descending | ForEach-Object { [regex]::Escape($_) }) -join '|'
  if ($IgnoreCase) {
    return [regex]::Replace($text, $pattern, { param($m) $map[$m.Value.ToUpperInvariant()] }, 'IgnoreCase')
  }
  return [regex]::Replace($text, $pattern, { param($m) $map[$m.Value] })
}

# --- settings for the new app ---
if (-not $Name) { $Name = (Read-Host 'New app name (e.g. project-1)').Trim() }
if ($Name -cnotmatch '^[a-z][a-z0-9]*(-[a-z0-9]+)*$' -or $Name.Length -gt 30) {
  Fail "app name '$Name': use up to 30 lower-case letters, digits and single hyphens, starting with a letter."
}
if ($Name -eq $app) { Fail "the new app needs a name other than $app." }
if (-not $HostName) { $HostName = "$Name.$apex" }
if ($HostName -ne $apex -and $HostName -notmatch "\.$([regex]::Escape($apex))$") { Fail "host $HostName is neither $apex nor under it (project.json domain.apex)." }
if (-not $Primary) { $Primary = $project.theme.primary }
if ($Primary -notmatch '^#[0-9A-Fa-f]{6}$') { Fail "colour ${Primary}: use #RRGGBB." }
$Primary = $Primary.ToUpperInvariant()
if (-not $CognitoPrefix) {
  $CognitoPrefix = $project.cognito.domainPrefix.Replace($app, $Name)
  if ($CognitoPrefix -eq $project.cognito.domainPrefix) { $CognitoPrefix = "$Name-$CognitoPrefix" }
}
# Cognito prefixes are global across AWS and may not contain aws, amazon or cognito.
if ($CognitoPrefix -cnotmatch '^[a-z0-9](-?[a-z0-9])*$' -or $CognitoPrefix -match 'aws|amazon|cognito' -or $CognitoPrefix.Length -gt 63) {
  Fail "Cognito domain prefix '$CognitoPrefix': use lower-case letters, digits and hyphens, without aws, amazon or cognito."
}
if (-not $Destination) { $Destination = Join-Path (Split-Path -Parent $root) $Name }
if (Test-Path $Destination) { Fail "$Destination already exists." }

$newPackage = 'com.acombsdev.' + ($Name -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
$newSchema = ($Name -replace '[^A-Za-z0-9]', '_').ToLowerInvariant()
# Old -> new, case-sensitive: e.g. template-0.acombs-dev.com, com/acombsdev/template0, template_0, Template 0.
$renames = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
$pairs = @(
  @($domain, $HostName),
  @($project.cognito.domainPrefix, $CognitoPrefix),
  @($javaPackage, $newPackage),
  @($javaPackage.Replace('.', '/'), $newPackage.Replace('.', '/')),
  @($dbSchema, $newSchema),
  @((DisplayName $app), (DisplayName $Name)),
  @($app, $Name),
  @(($app -replace '[^A-Za-z0-9]', '').ToLowerInvariant(), ($Name -replace '[^A-Za-z0-9]', '').ToLowerInvariant())
)
# A display name set in project.json gives way to one made from the new app's name.
if ($project.displayName) { $pairs = ,@($project.displayName, (DisplayName $Name)) + $pairs }
foreach ($p in $pairs) { if (-not $renames.ContainsKey($p[0])) { $renames[$p[0]] = $p[1] } }
$colours = New-Object 'System.Collections.Generic.Dictionary[string,string]' 
if ($Primary -ne $project.theme.primary.ToUpperInvariant()) { $colours[$project.theme.primary.ToUpperInvariant()] = $Primary }
Step "new app $Name at $Destination"
Step "host $HostName, Cognito prefix $CognitoPrefix, schema $newSchema, package $newPackage, colour $Primary"

# --- copy and rename ---
$files = & git -C $root -c core.quotepath=off ls-files --cached --others --exclude-standard
if ($LASTEXITCODE -ne 0) { Fail 'git ls-files failed; the template must be a git repository.' }
$dirty = & git -C $root status --porcelain
if ($dirty) { Step 'note: the template has uncommitted changes; they are copied as they are now' }
$themeFile = "$app-ui/src/app/theme/generated_theme-colors.scss"
$settingsFile = "$app-ui/src/app/project.settings.ts"
$copied = 0; $changed = 0
foreach ($rel in ($files | Sort-Object -Unique)) {
  $source = Join-Path $root $rel
  if (-not (Test-Path $source -PathType Leaf)) { continue }   # deleted but not yet committed
  $target = Join-Path $Destination (Replace-All $rel $renames)
  New-Item -ItemType Directory -Force (Split-Path -Parent $target) | Out-Null
  $bytes = [System.IO.File]::ReadAllBytes($source)
  if ([Array]::IndexOf($bytes, [byte]0) -ge 0) {
    [System.IO.File]::WriteAllBytes($target, $bytes)        # binary
  } else {
    $text = $utf8.GetString($bytes)
    $new = Replace-All $text $renames
    # The palettes stay as they are; start-all regenerates them when project.json's colours differ.
    if ($rel -ne $themeFile) { $new = Replace-All $new $colours -IgnoreCase }
    if ($rel -eq $settingsFile) { $new = $new -replace "(userPoolId|userPoolClientId|domain): '[^']*'", "`$1: ''" }
    if ($new -cne $text) { $changed++ }
    Write-Utf8 $target $new
  }
  $copied++
}
Step "copied $copied files ($changed with renamed text)"

# project.json was renamed like the other files; check it says what was asked.
$newProject = Get-Content (Join-Path $Destination 'project.json') -Raw | ConvertFrom-Json
if ($newProject.name -ne $Name -or $newProject.domain.host -ne $HostName -or $newProject.cognito.domainPrefix -ne $CognitoPrefix -or
    $newProject.theme.primary -ne $Primary) {
  Fail "project.json in $Destination did not come out as expected; check it by hand."
}
if ($newProject.database.schema) { Step "note: project.json sets database.schema $($newProject.database.schema); remove it to use $newSchema" }
Step 'project.json written'

# The new .env keeps only the shared database login (and port); the app's schema is its own, and
# its Cognito IDs come from its own config\cognito-pool.json once create-cognito-pool has run.
$envFile = Join-Path $apiDir '.env'
if (Test-Path $envFile) {
  $keep = Get-Content $envFile | Where-Object { $_ -match '^\s*(DATABASE_URL|DATABASE_USERNAME|DATABASE_PASSWORD|SERVER_PORT)\s*=' }
  $lines = @("# Local-only settings for $Name-api (git-ignored). Database login shared with the other apps.") +
    $keep + @("DATABASE_SCHEMA=$newSchema")
  Write-Utf8 (Join-Path $Destination "$Name-api\.env") (($lines -join "`n") + "`n")
  Step "$Name-api\.env written with the shared database login and schema $newSchema (git-ignored)"
} else { Step "note: no .env to copy; create $Name-api\.env before apply-migrations and deploy-api" }

$left = Get-ChildItem $Destination -Recurse -File | Select-String -Pattern $app -SimpleMatch -List
if ($left) { Step "note: '$app' still appears in: $(($left.Path | ForEach-Object { $_.Substring($Destination.Length + 1) }) -join ', ')" }

if (-not $NoGit) {
  & git -C $Destination init -q -b main
  & git -C $Destination add -A
  & git -C $Destination commit -q -m "Create $Name from $app"
  if ($LASTEXITCODE -ne 0) { Fail 'git commit failed; the files are in place, commit them yourself.' }
  Step 'git repository started with one commit (no remote)'
}

Step "DONE. Next, from $Destination in PowerShell (see README.md, Create a new app):"
Step '  1. scripts\create-cognito-pool.ps1    2. scripts\apply-migrations.ps1    3. scripts\start-all.ps1'
Step '  4. scripts\deploy-api.ps1, create-function-url.ps1'
Step '  5. scripts\request-certificate.ps1 (writes its DNS records to Route 53 and waits for the certificates)'
Step '  6. scripts\create-ui-bucket.ps1, create-cloudfront.ps1, create-api-cloudfront.ps1 (with their DNS records)'
Step '  7. push to GitHub, scripts\create-github-deploy-role.ps1, then run the CI workflow to deploy'
Read-Host 'Press Enter to close'

# Setup step 1 (database): creates the app's schema in the shared database and applies
# <app>-api\db\migrations\*.sql to it (see ApplyMigrations.java). Safe to re-run: migrations are
# idempotent. -DryRun applies them and rolls back. Needs <app>-api\.env and the PostgreSQL driver
# in ~\.m2 (any Maven build of the API downloads it). Log: logs\migrations.log
param([switch]$DryRun)
. "$PSScriptRoot\common.ps1" -LogName 'migrations.log' -Title 'database migrations'

$pgJar = Get-ChildItem "$env:USERPROFILE\.m2\repository\org\postgresql\postgresql" -Recurse -Filter 'postgresql-*.jar' -ErrorAction SilentlyContinue |
  Where-Object Name -notmatch 'sources' | Sort-Object { [version]($_.Directory.Name -replace '[^0-9.]', '') } | Select-Object -Last 1
if (-not $pgJar) { Fail 'PostgreSQL driver not found in ~\.m2. Run scripts\start-all.ps1 (or any Maven build of the API) first.' }
if (-not (Test-Path (Join-Path $apiDir '.env'))) { Fail ".env not found in $app-api." }
Step "schema: $dbSchema$(if ($DryRun) { ' (dry run)' })"

$argv = @('--class-path', $pgJar.FullName, (Join-Path $PSScriptRoot 'ApplyMigrations.java'), $apiDir, $dbSchema)
if ($DryRun) { $argv += '--dry-run' }
& java @argv 2>&1 | ForEach-Object { Step "$_" }
if ($LASTEXITCODE -ne 0) { Fail "migrations failed (exit $LASTEXITCODE); see logs\migrations.log" }
Step 'DONE.'
Read-Host 'Press Enter to close'

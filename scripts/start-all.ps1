# Full stack: first-time setup, verification and local start.
# Writes logs to ..\logs. Safe to re-run; setup steps are skipped when already done.
. "$PSScriptRoot\common.ps1" -LogName 'status.log' -Title 'setup'
$env:NG_CLI_ANALYTICS = 'false'
$ui   = $uiDir
$api  = $apiDir
$primary = $project.theme.primary
$secondary = $project.theme.secondary
function Run($name, $dir, $exe, [string[]]$argv) {
  Step "START $name"
  Push-Location $dir
  try { & $exe @argv *>&1 | Tee-Object -FilePath (Join-Path $logs "$name.log") | Out-Host; $code = $LASTEXITCODE }
  finally { Pop-Location }
  Step "END $name exit=$code"
  if ($code -ne 0) { throw "$name failed (exit $code). See logs\$name.log" }
}
try {
  # --- Java 21 ---
  $javaOk = $false
  try { $v = (& java -version 2>&1 | Out-String); $javaOk = $v -match 'version "21' } catch {}
  if (-not $javaOk) {
    $jdk = Get-ChildItem "$env:USERPROFILE\.jdks" -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match '21' -and (Test-Path (Join-Path $_.FullName 'bin\java.exe')) } | Select-Object -First 1
    if (-not $jdk) { throw 'Java 21 not found on PATH or in %USERPROFILE%\.jdks. Install JDK 21.' }
    $env:JAVA_HOME = $jdk.FullName; $env:Path = "$($jdk.FullName)\bin;$env:Path"
  }
  Step "java: $((& java -version 2>&1 | Select-Object -First 1))"
  # --- Maven ---
  $mvn = (Get-Command mvn.cmd -ErrorAction SilentlyContinue).Source
  if (-not $mvn) {
    $cands = @("$env:ProgramFiles\JetBrains", "$env:LOCALAPPDATA\Programs", "$env:USERPROFILE\.m2\wrapper\dists", "$env:LOCALAPPDATA\JetBrains\Toolbox\apps") |
      Where-Object { Test-Path $_ } | ForEach-Object { Get-ChildItem $_ -Recurse -Filter mvn.cmd -ErrorAction SilentlyContinue } |
      Where-Object { $_.FullName -match '\\bin\\mvn.cmd$' }
    $mvn = ($cands | Select-Object -First 1).FullName
  }
  if (-not $mvn) { throw 'Maven not found (PATH, IntelliJ bundle or ~/.m2/wrapper). Install Maven 3.9+.' }
  Step "maven: $mvn"
  $npm = 'Invoke-Npm'
  if (-not $nodeExe) { throw 'Node.js/npm not found on PATH. Install Node.js 22 LTS.' }
  Step "node: $(& node -v), npm $(Invoke-Npm @('-v'))"
  # --- UI setup ---
  if (-not (Test-Path (Join-Path $ui 'node_modules\.bin\ng.cmd'))) { Run 'ui-npm-ci' $ui $npm @('ci','--no-audit','--no-fund') }
  $theme = Join-Path $ui 'src\app\theme\generated_theme-colors.scss'
  # Regenerated when either colour in project.json differs from the ones the palettes came from.
  if (-not (Select-String -Path $theme -Pattern "generated from primary: $primary, secondary: $secondary" -SimpleMatch -Quiet)) {
    # The schematic writes <directory>_theme-colors.scss, i.e. src/app/theme/_generated_theme-colors.scss.
    Run 'ui-theme' $ui (Join-Path $ui 'node_modules\.bin\ng.cmd') @('generate','@angular/material:theme-color',"--primary-color=$primary","--secondary-color=$secondary",'--directory=src/app/theme/_generated','--is-scss','--interactive=false')
    $gen = Join-Path $ui 'src\app\theme\_generated_theme-colors.scss'
    if (-not (Test-Path $gen)) { throw "theme generator produced no file at $gen" }
    Copy-Item $gen $theme -Force -ErrorAction Stop
    Step "theme: generated from primary $primary, secondary $secondary"
  }
  $stray = Join-Path $ui 'src\app\theme\_generated_theme-colors.scss'
  if (Test-Path $stray) { Remove-Item $stray -Force }
  Sync-UiConfig
  Run 'ui-build' $ui $npm @('run','build')
  Run 'ui-test'  $ui $npm @('test','--','--watch=false')
  # --- API verify ---
  Run 'api-verify' $api $mvn @('--batch-mode','--no-transfer-progress','verify')
  # --- Start both (each in its own window, logging to logs\) ---
  # The API reads its schema and user pool from here and its database login from .env.
  $ids = Get-CognitoIds
  $apiCmd = "`$env:JAVA_HOME='$env:JAVA_HOME'; `$env:Path='$env:Path'; `$env:DATABASE_SCHEMA='$dbSchema'; `$env:COGNITO_ISSUER='$($ids.issuer)'; `$env:COGNITO_CLIENT_ID='$($ids.userPoolClientId)'; Set-Location '$api'; & '$mvn' spring-boot:run *>&1 | Tee-Object '$logs\api-run.log'"
  $uiCmd  = "Set-Location '$ui'; $npmCommand start *>&1 | Tee-Object '$logs\ui-run.log'"
  Start-Process powershell -ArgumentList '-NoExit','-NoProfile','-Command',$apiCmd -WindowStyle Normal
  Start-Process powershell -ArgumentList '-NoExit','-NoProfile','-Command',$uiCmd -WindowStyle Normal
  Step 'STARTED api (http://localhost:8080) and ui (http://localhost:4200)'
} catch {
  Step "FAILED: $($_.Exception.Message)"
  Write-Host "`nSetup failed: $($_.Exception.Message)" -ForegroundColor Red
  Read-Host 'Press Enter to close'
  exit 1
}
Step 'DONE'
Start-Sleep 5

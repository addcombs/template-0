# Runs the UI unit tests and the API verify build without starting servers.
# Logs: logs\test-ui.log and logs\test-api.log (full output), logs\test-all.log (summary)
. "$PSScriptRoot\common.ps1" -LogName 'test-all.log' -Title 'tests'

# Runs a native command in $dir, writing its output to logs\$logName; returns the exit code.
function Run-Logged($dir, $logName, $exe, [string[]]$argv) {
  Push-Location $dir
  & $exe @argv *>&1 | ForEach-Object { "$_" } | Set-Content (Join-Path $logs $logName)
  $code = $LASTEXITCODE
  Pop-Location
  return $code
}

Step 'running the UI tests...'
$ui = Run-Logged $uiDir 'test-ui.log' 'npm.cmd' @('test', '--', '--watch=false')
Step "UI tests exit code $ui"
Step 'running the API verify build...'
$api = Run-Logged $apiDir 'test-api.log' 'mvn.cmd' @('--batch-mode', '--no-transfer-progress', 'verify')
Step "API verify exit code $api"
if ($ui -ne 0 -or $api -ne 0) { Fail 'tests failed; see logs\test-ui.log and logs\test-api.log' }
Step 'DONE. All tests passed.'
Read-Host 'Press Enter to close'

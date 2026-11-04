# Builds and tests the API Lambda package, <app>-api\target\*-lambda.zip, which deploy-api.ps1
# uploads. Log: logs\build-lambda.log (the full Maven output)
. "$PSScriptRoot\common.ps1" -LogName 'build-lambda.log' -Title 'Lambda build'
Step 'building the Lambda package...'
Push-Location $apiDir
& mvn.cmd -P lambda --batch-mode --no-transfer-progress package *>&1 | ForEach-Object { "$_" } | Add-Content $log
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { Fail "Maven build failed (exit $code); see logs\build-lambda.log" }
$zip = Get-ChildItem (Join-Path $apiDir 'target\*-lambda.zip') | Sort-Object LastWriteTime | Select-Object -Last 1
Step "DONE. $($zip.Name) ($([math]::Round($zip.Length / 1MB, 1)) MB)"
Read-Host 'Press Enter to close'

# Saves the last 30 minutes of the API's Lambda logs to logs\api-lambda.log.
. "$PSScriptRoot\common.ps1" -LogName 'api-lambda.log' -Title 'Lambda logs'
Invoke-AwsCli @('logs','tail',"/aws/lambda/$($names.Function)",'--since','30m','--format','short') -AllowFail | Out-Null
Write-Host "Saved to logs\api-lambda.log (exit code $LASTEXITCODE)"
Read-Host 'Press Enter to close'

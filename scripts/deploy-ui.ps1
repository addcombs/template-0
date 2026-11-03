# Setup step 6 (UI): writes the UI settings, builds the UI for production, uploads it to the
# private UI bucket, and refreshes CloudFront's copy of index.html. Re-run after every UI change.
# Log: logs\deploy-ui.log
. "$PSScriptRoot\common.ps1" -LogName 'deploy-ui.log' -Title 'UI deploy'
# Angular builds to dist\<angular.json project name>\browser.
$ngProject = ((Get-Content (Join-Path $uiDir 'angular.json') -Raw | ConvertFrom-Json).projects.PSObject.Properties | Select-Object -First 1).Name
$dist = Join-Path $uiDir "dist\$ngProject\browser"

$account = Invoke-AwsCli @('sts','get-caller-identity','--query','Account','--output','text')
$bucket = UiBucket $account
$distId = Invoke-AwsCli @('cloudfront','list-distributions','--query',"DistributionList.Items[?Aliases.Items && contains(Aliases.Items, '$domain')].Id | [0]",'--output','text')
if (-not $distId -or $distId -eq 'None') { Fail "No CloudFront distribution for $domain. Run create-cloudfront.cmd first." }
Step "bucket: $bucket, distribution: $distId"

Sync-UiConfig
Step 'building the UI (production)...'
Push-Location $uiDir
& npm.cmd run build *>&1 | Tee-Object -FilePath (Join-Path $logs 'deploy-ui-build.log') | Out-Host
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { Fail "npm run build (exit $code); see logs\deploy-ui-build.log" }
if (-not (Test-Path (Join-Path $dist 'index.html'))) { Fail "build output not found at $dist" }
Step "build done: $((Get-ChildItem $dist -Recurse -File | Measure-Object).Count) files"

# Hashed assets can be cached for a year; index.html must always be re-checked.
Invoke-AwsCli @('s3','sync',$dist,"s3://$bucket",'--delete','--exclude','index.html','--cache-control','public,max-age=31536000,immutable','--only-show-errors') | Out-Null
Invoke-AwsCli @('s3','cp',(Join-Path $dist 'index.html'),"s3://$bucket/index.html",'--cache-control','no-cache','--content-type','text/html','--only-show-errors') | Out-Null
Step 'uploaded to S3'
$inv = Invoke-AwsCli @('cloudfront','create-invalidation','--distribution-id',$distId,'--paths','/index.html','/','--query','Invalidation.Id','--output','text')
Step "CloudFront refresh requested: $inv (takes a minute or two)"
Step "DONE. Open https://$domain/"
Read-Host 'Press Enter to close'

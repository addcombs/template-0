# One-off, after provision.ps1 -ImportExisting has moved an app onto the CDK stack and the site
# works: deletes what the old setup scripts made that the stack does not use.
#  - the old CloudFront distributions for the host and api.<host> (disabled first, which takes
#    5-15 minutes), and the UI's old origin access control
#  - api.<host>'s DNS records, and the old per-host certificates with their validation records
#  - the old function URL and sign-up trigger permissions, and the deploy role's old inline policy
# Safe to re-run: whatever is already gone is skipped. Log: logs\remove-old-setup.log
. "$PSScriptRoot\common.ps1" -LogName 'remove-old-setup.log' -Title 'remove old setup'
$apiHost = "api.$domain"
$zoneId = Get-HostedZoneId
$stackDist = Invoke-AwsCli @('cloudformation','describe-stacks','--stack-name',$app,'--query',"Stacks[0].Outputs[?OutputKey=='DistributionId'].OutputValue | [0]",'--output','text') -AllowFail
if (-not $stackDist -or $stackDist -eq 'None') { Fail "the $app stack has no distribution yet; run scripts\provision.ps1 -ImportExisting first." }

# --- old distributions: the scripts' comments were "<app> UI" and "<app> API" ---
$old = Invoke-AwsCli @('cloudfront','list-distributions','--query',"DistributionList.Items[?Comment=='$app UI' || Comment=='$app API'].Id",'--output','text')
$oldIds = @("$old" -split '\s+' | Where-Object { $_ -and $_ -ne 'None' -and $_ -ne $stackDist })
foreach ($id in $oldIds) {
  $current = Invoke-AwsCli @('cloudfront','get-distribution-config','--id',$id,'--output','json') | ConvertFrom-Json
  if ($current.DistributionConfig.Enabled) {
    $current.DistributionConfig.Enabled = $false
    # Its alias (api.<host>) goes too, so nothing points at it while it is deleted.
    $current.DistributionConfig.Aliases = [ordered]@{ Quantity = 0 }
    $configFile = Write-Json (Join-Path $logs 'old-distribution-config.json') $current.DistributionConfig
    Invoke-AwsCli @('cloudfront','update-distribution','--id',$id,'--if-match',$current.ETag,'--distribution-config',"file://$configFile",'--query','Distribution.Status','--output','text') | Out-Null
    Step "distribution $id disabled"
  }
}
# api.<host>'s records pointed at the old API distribution.
$records = Invoke-AwsCli @('route53','list-resource-record-sets','--hosted-zone-id',$zoneId,'--start-record-name',"$apiHost.",'--output','json') | ConvertFrom-Json
$apiRecords = @($records.ResourceRecordSets | Where-Object { $_.Name -eq "$apiHost." -and $_.Type -in 'A', 'AAAA', 'CNAME' })
if ($apiRecords) {
  $batch = Write-Json (Join-Path $logs 'dns-change.json') @{ Changes = @($apiRecords | ForEach-Object { @{ Action = 'DELETE'; ResourceRecordSet = $_ } }) }
  Invoke-AwsCli @('route53','change-resource-record-sets','--hosted-zone-id',$zoneId,'--change-batch',"file://$batch") | Out-Null
  Step "DNS records for $apiHost removed"
}
foreach ($id in $oldIds) {
  Step "waiting for distribution $id to finish disabling (5-15 minutes)..."
  Invoke-AwsCli @('cloudfront','wait','distribution-deployed','--id',$id) | Out-Null
  $etag = Invoke-AwsCli @('cloudfront','get-distribution-config','--id',$id,'--query','ETag','--output','text')
  Invoke-AwsCli @('cloudfront','delete-distribution','--id',$id,'--if-match',$etag) | Out-Null
  Step "distribution $id deleted"
}
$oacId = Invoke-AwsCli @('cloudfront','list-origin-access-controls','--query',"OriginAccessControlList.Items[?Name=='$app-ui-oac'].Id | [0]",'--output','text')
if ($oacId -and $oacId -ne 'None') {
  $etag = Invoke-AwsCli @('cloudfront','get-origin-access-control','--id',$oacId,'--query','ETag','--output','text')
  Invoke-AwsCli @('cloudfront','delete-origin-access-control','--id',$oacId,'--if-match',$etag) | Out-Null
  Step "origin access control $app-ui-oac deleted"
}

# --- old certificates, and their validation records ---
foreach ($certDomain in $domain, $apiHost) {
  $arn = Invoke-AwsCli @('acm','list-certificates','--query',"CertificateSummaryList[?DomainName=='$certDomain'].CertificateArn | [0]",'--output','text') -Region $cloudFrontRegion
  if (-not $arn -or $arn -eq 'None') { continue }
  $rec = Invoke-AwsCli @('acm','describe-certificate','--certificate-arn',$arn,'--query','Certificate.DomainValidationOptions[0].ResourceRecord.Name','--output','text') -Region $cloudFrontRegion
  Invoke-AwsCli @('acm','delete-certificate','--certificate-arn',$arn) -Region $cloudFrontRegion | Out-Null
  Step "certificate for $certDomain deleted"
  if ($rec -and $rec -ne 'None') {
    $found = Invoke-AwsCli @('route53','list-resource-record-sets','--hosted-zone-id',$zoneId,'--start-record-name',$rec,'--max-items','1','--output','json') | ConvertFrom-Json
    $cname = @($found.ResourceRecordSets | Where-Object { $_.Name -eq $rec -and $_.Type -eq 'CNAME' })
    if ($cname) {
      $batch = Write-Json (Join-Path $logs 'dns-change.json') @{ Changes = @(@{ Action = 'DELETE'; ResourceRecordSet = $cname[0] }) }
      Invoke-AwsCli @('route53','change-resource-record-sets','--hosted-zone-id',$zoneId,'--change-batch',"file://$batch") | Out-Null
      Step "validation record $rec removed"
    }
  }
}

# --- permissions and policies the stack replaced with its own ---
foreach ($sid in 'FunctionURLAllowPublicAccess', 'FunctionURLAllowInvokeAction') {
  if ($null -ne (Invoke-AwsCli @('lambda','remove-permission','--function-name',"$app-api",'--qualifier','live','--statement-id',$sid) -AllowFail -Quiet)) { Step "old function URL permission $sid removed" }
}
if ($null -ne (Invoke-AwsCli @('lambda','remove-permission','--function-name',"$app-auto-confirm",'--statement-id','cognito-pre-sign-up') -AllowFail -Quiet)) { Step 'old sign-up trigger permission removed' }
if ($null -ne (Invoke-AwsCli @('iam','delete-role-policy','--role-name',"$app-github-deploy",'--policy-name','deploy') -AllowFail -Quiet)) { Step 'deploy role''s old inline policy removed' }

Step "DONE. Only the $app stack's resources are left."
Wait-Close

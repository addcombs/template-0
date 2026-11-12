# Setup step 5: creates the CloudFront distribution for the app's domain (the UI only; the API has
# its own distribution at api.<domain>, see create-api-cloudfront.ps1).
#  - origin access control so only CloudFront can read the private UI bucket
#  - default behavior -> S3 bucket (CachingOptimized)
#  - the ACM certificate and the domain alias
#  - a bucket policy allowing only this distribution to read the bucket
#  - alias A/AAAA records for the domain in Route 53
# Safe to re-run: reuses the access control and an existing distribution for the alias.
# Log: logs\cloudfront.log
. "$PSScriptRoot\common.ps1" -LogName 'cloudfront.log' -Title 'CloudFront'
$oacName = $names.Oac
# AWS managed policy IDs
$cachingOptimized = '658327ea-f89d-4fab-a63d-7e88639e58f6'

$account = Invoke-AwsCli @('sts','get-caller-identity','--query','Account','--output','text')
$bucket = UiBucket $account
$bucketHost = "$bucket.s3.$awsRegion.amazonaws.com"
$certArn = Invoke-AwsCli @('acm','list-certificates','--certificate-statuses','ISSUED','--query',"CertificateSummaryList[?DomainName=='$domain'].CertificateArn | [0]",'--output','text') -Region $cloudFrontRegion
if (-not $certArn -or $certArn -eq 'None') { Fail "No ISSUED certificate for $domain in $cloudFrontRegion. Run scripts\request-certificate.ps1 first." }
Step "account: $account, bucket: $bucket, certificate: $certArn"

# --- origin access control ---
$oacId = Invoke-AwsCli @('cloudfront','list-origin-access-controls','--query',"OriginAccessControlList.Items[?Name=='$oacName'].Id | [0]",'--output','text')
if (-not $oacId -or $oacId -eq 'None') {
  $oacId = Invoke-AwsCli @('cloudfront','create-origin-access-control','--origin-access-control-config',
    "Name=$oacName,SigningProtocol=sigv4,SigningBehavior=always,OriginAccessControlOriginType=s3",'--query','OriginAccessControl.Id','--output','text')
  Step "origin access control created: $oacId"
} else { Step "origin access control exists: $oacId" }

# --- distribution ---
$existing = Invoke-AwsCli @('cloudfront','list-distributions','--query',"DistributionList.Items[?Aliases.Items && contains(Aliases.Items, '$domain')].[Id,DomainName,ARN] | [0]",'--output','text')
if ($existing -and $existing -ne 'None') {
  $distId, $distDomain, $distArn = $existing -split '\s+'
  Step "distribution exists: $distId ($distDomain)"
} else {
  $readMethods = @{ Quantity = 2; Items = @('GET','HEAD'); CachedMethods = @{ Quantity = 2; Items = @('GET','HEAD') } }
  $distConfig = [ordered]@{
    CallerReference = "$app-$(Get-Date -Format yyyyMMddHHmmss)"
    Comment = "$app UI"
    Enabled = $true
    Aliases = @{ Quantity = 1; Items = @($domain) }
    DefaultRootObject = 'index.html'
    Origins = @{ Quantity = 1; Items = @(
      [ordered]@{ Id = 's3-ui'; DomainName = $bucketHost; OriginPath = ''; CustomHeaders = @{ Quantity = 0 };
        S3OriginConfig = @{ OriginAccessIdentity = '' }; OriginAccessControlId = $oacId }
    ) }
    DefaultCacheBehavior = [ordered]@{ TargetOriginId = 's3-ui'; ViewerProtocolPolicy = 'redirect-to-https';
      AllowedMethods = $readMethods; Compress = $true; CachePolicyId = $cachingOptimized }
    ViewerCertificate = [ordered]@{ ACMCertificateArn = $certArn; SSLSupportMethod = 'sni-only'; MinimumProtocolVersion = 'TLSv1.2_2021' }
    PriceClass = 'PriceClass_100'
    HttpVersion = 'http2and3'
    IsIPV6Enabled = $true
  }
  $configFile = Write-Json (Join-Path $logs 'cloudfront-config.json') $distConfig
  $created = Invoke-AwsCli @('cloudfront','create-distribution','--distribution-config',"file://$configFile",'--query','Distribution.[Id,DomainName,ARN]','--output','text')
  $distId, $distDomain, $distArn = $created -split '\s+'
  Step "distribution created: $distId ($distDomain)"
}

# --- bucket policy: only this distribution may read ---
$policy = '{"Version":"2012-10-17","Statement":[{"Sid":"AllowCloudFrontRead","Effect":"Allow","Principal":{"Service":"cloudfront.amazonaws.com"},"Action":"s3:GetObject","Resource":"arn:aws:s3:::' + $bucket + '/*","Condition":{"StringEquals":{"AWS:SourceArn":"' + $distArn + '"}}}]}'
$policyFile = Join-Path $logs 'ui-bucket-policy.json'
Write-Utf8 $policyFile $policy
Invoke-AwsCli @('s3api','put-bucket-policy','--bucket',$bucket,'--policy',"file://$policyFile") | Out-Null
Step "bucket policy set: only $distId can read $bucket"

$status = Invoke-AwsCli @('cloudfront','get-distribution','--id',$distId,'--query','Distribution.Status','--output','text')
Step "status: $status (InProgress -> Deployed takes about 5-15 minutes)"
Set-CloudFrontAlias $domain $distDomain
Step "DONE. Distribution $distId at $distDomain; https://$domain/ serves the UI once it is deployed"
Read-Host 'Press Enter to close'

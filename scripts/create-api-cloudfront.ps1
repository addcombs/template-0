# Setup step 5 (API): creates the CloudFront distribution for the API domain (api.<domain>).
#  - one origin: the Lambda function URL of the `live` alias
#  - every path -> the API (CachingDisabled + AllViewerExceptHostHeader, which forwards the
#    Authorization header and the CORS request headers; the API answers CORS itself)
#  - the ACM certificate for the API domain and the alias
#  - alias A/AAAA records for the API domain in Route 53
# Safe to re-run: reuses an existing distribution for the alias.
# Log: logs\api-cloudfront.log
. "$PSScriptRoot\common.ps1" -LogName 'api-cloudfront.log' -Title 'API CloudFront'
# AWS managed policy IDs
$cachingDisabled  = '4135ea2d-6df8-44a3-9df3-4b5a84be39ad'
$allViewerExceptHost = 'b689b0a8-53d0-40ab-baf2-68738e2966ac'

$certArn = Invoke-AwsCli @('acm','list-certificates','--certificate-statuses','ISSUED','--query',"CertificateSummaryList[?DomainName=='$apiDomain'].CertificateArn | [0]",'--output','text') -Region $cloudFrontRegion
if (-not $certArn -or $certArn -eq 'None') { Fail "No ISSUED certificate for $apiDomain in $cloudFrontRegion. Run scripts\request-certificate.ps1 first." }
$fnUrl = Invoke-AwsCli @('lambda','get-function-url-config','--function-name',$names.Function,'--qualifier','live','--query','FunctionUrl','--output','text') -AllowFail
if (-not $fnUrl) { Fail "No function URL on $($names.Function):live. Run scripts\create-function-url.ps1 first." }
$fnHost = ([uri]$fnUrl).Host
Step "certificate: $certArn, API: $fnHost"

$existing = Invoke-AwsCli @('cloudfront','list-distributions','--query',"DistributionList.Items[?Aliases.Items && contains(Aliases.Items, '$apiDomain')].[Id,DomainName] | [0]",'--output','text')
if ($existing -and $existing -ne 'None') {
  $distId, $distDomain = $existing -split '\s+'
  Step "distribution exists: $distId ($distDomain)"
} else {
  $distConfig = [ordered]@{
    CallerReference = "$app-api-$(Get-Date -Format yyyyMMddHHmmss)"
    Comment = "$app API"
    Enabled = $true
    Aliases = @{ Quantity = 1; Items = @($apiDomain) }
    Origins = @{ Quantity = 1; Items = @(
      [ordered]@{ Id = 'lambda-api'; DomainName = $fnHost; OriginPath = ''; CustomHeaders = @{ Quantity = 0 };
        CustomOriginConfig = [ordered]@{ HTTPPort = 80; HTTPSPort = 443; OriginProtocolPolicy = 'https-only';
          OriginSslProtocols = @{ Quantity = 1; Items = @('TLSv1.2') }; OriginReadTimeout = 30; OriginKeepaliveTimeout = 5 } }
    ) }
    DefaultCacheBehavior = [ordered]@{ TargetOriginId = 'lambda-api'; ViewerProtocolPolicy = 'redirect-to-https';
      AllowedMethods = @{ Quantity = 7; Items = @('GET','HEAD','OPTIONS','PUT','POST','PATCH','DELETE'); CachedMethods = @{ Quantity = 2; Items = @('GET','HEAD') } };
      Compress = $true; CachePolicyId = $cachingDisabled; OriginRequestPolicyId = $allViewerExceptHost }
    ViewerCertificate = [ordered]@{ ACMCertificateArn = $certArn; SSLSupportMethod = 'sni-only'; MinimumProtocolVersion = 'TLSv1.2_2021' }
    PriceClass = 'PriceClass_100'
    HttpVersion = 'http2and3'
    IsIPV6Enabled = $true
  }
  $configFile = Write-Json (Join-Path $logs 'api-cloudfront-config.json') $distConfig
  $created = Invoke-AwsCli @('cloudfront','create-distribution','--distribution-config',"file://$configFile",'--query','Distribution.[Id,DomainName]','--output','text')
  $distId, $distDomain = $created -split '\s+'
  Step "distribution created: $distId ($distDomain)"
}

$status = Invoke-AwsCli @('cloudfront','get-distribution','--id',$distId,'--query','Distribution.Status','--output','text')
Step "status: $status (InProgress -> Deployed takes about 5-15 minutes)"
Set-CloudFrontAlias $apiDomain $distDomain
Step "DONE. Distribution $distId at $distDomain; the API will answer at https://$apiDomain/actuator/health"
Read-Host 'Press Enter to close'

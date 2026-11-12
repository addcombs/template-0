# Setup step 5 (first part): requests the free ACM certificates for the app's domain and its API
# domain (api.<domain>) in us-east-1 (the only region CloudFront uses) with DNS validation, writes
# the validation CNAMEs to the Route 53 zone, and waits until both are issued. Safe to re-run: it
# never requests a duplicate, and the CNAMEs stay so ACM can renew the certificates.
# Log: logs\certificate.log
. "$PSScriptRoot\common.ps1" -LogName 'certificate.log' -Title 'certificate'

$pending = @()
$records = @()
foreach ($cert in @(@{ Domain = $domain; Token = $names.CertToken }, @{ Domain = $apiDomain; Token = $names.ApiCertToken })) {
  $certDomain = $cert.Domain
  # Reuse an existing certificate for the domain (pending or issued) instead of requesting another.
  $arn = Invoke-AwsCli @('acm','list-certificates','--certificate-statuses','PENDING_VALIDATION','ISSUED',
    '--query',"CertificateSummaryList[?DomainName=='$certDomain'].CertificateArn | [0]",'--output','text') -Region $cloudFrontRegion
  if (-not $arn -or $arn -eq 'None') {
    $arn = Invoke-AwsCli @('acm','request-certificate','--domain-name',$certDomain,'--validation-method','DNS',
      '--idempotency-token',$cert.Token,'--query','CertificateArn','--output','text') -Region $cloudFrontRegion
    Step "$certDomain certificate requested: $arn"
  } else { Step "$certDomain certificate already exists: $arn" }

  # ACM needs a few seconds to generate the validation record.
  $name = $null; $value = $null; $status = $null
  for ($i = 0; $i -lt 12 -and -not $name; $i++) {
    $rec = Invoke-AwsCli @('acm','describe-certificate','--certificate-arn',$arn,'--query',
      'Certificate.[Status, DomainValidationOptions[0].ResourceRecord.Name, DomainValidationOptions[0].ResourceRecord.Value]','--output','text') -Region $cloudFrontRegion
    $status, $name, $value = $rec -split '\s+'
    if (-not $name -or $name -eq 'None') { $name = $null; Start-Sleep 5 }
  }
  if (-not $name) { Fail "ACM did not return a validation record for $certDomain yet; run this again in a minute." }
  Step "$certDomain status: $status"
  if ($status -ne 'ISSUED') { $pending += @{ Domain = $certDomain; Arn = $arn } }
  $records += [ordered]@{ Name = $name; Type = 'CNAME'; TTL = 300; ResourceRecords = @(@{ Value = $value }) }
}
Set-DnsRecords "$app certificate validation" $records

# ACM checks the records every minute or so; issuing usually takes a few minutes.
foreach ($cert in $pending) {
  Step "waiting for $($cert.Domain) to be issued..."
  Invoke-AwsCli @('acm','wait','certificate-validated','--certificate-arn',$cert.Arn) -Region $cloudFrontRegion -AllowFail | Out-Null
  $status = Invoke-AwsCli @('acm','describe-certificate','--certificate-arn',$cert.Arn,'--query','Certificate.Status','--output','text') -Region $cloudFrontRegion
  Step "$($cert.Domain) status: $status"
  if ($status -ne 'ISSUED') { Fail "$($cert.Domain) is $status. Run scripts\request-certificate.ps1 again later." }
}
Step 'DONE. Both certificates are ISSUED and ready for CloudFront.'
Read-Host 'Press Enter to close'

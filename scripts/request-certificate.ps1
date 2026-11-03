# Setup step 5 (first part): requests the free ACM certificates for the app's domain and its API
# domain (api.<domain>) in us-east-1 (the only region CloudFront uses) with DNS validation, then
# prints the CNAME records to add at the DNS provider. Re-run any time to see the certificates'
# status; it never requests a duplicate.
# Log: logs\certificate.log
. "$PSScriptRoot\common.ps1" -LogName 'certificate.log' -Title 'certificate'

$allIssued = $true
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
  if ($status -ne 'ISSUED') { $allIssued = $false }
  $host_ = $name.TrimEnd('.') -replace "\.$([regex]::Escape($apex))$", ''
  $target = $value.TrimEnd('.')
  Step "Add this record at $($project.domain.dnsProvider) (Domains > $apex > DNS Settings > Custom Records):"
  Step "  Type:      CNAME"
  Step "  Host:      $host_"
  Step "  Points to: $target"
}
if ($allIssued) { Step 'DONE. Both certificates are ISSUED and ready for CloudFront.' }
else { Step 'DONE. After adding the records, run request-certificate.cmd again in a few minutes to see ISSUED.' }
Read-Host 'Press Enter to close'

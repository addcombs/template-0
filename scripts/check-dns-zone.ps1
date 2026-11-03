# Read-only: lists Route 53 hosted zones for the app's apex domain in this account and their name servers.
# Log: logs\dns-zone.log
. "$PSScriptRoot\common.ps1" -LogName 'dns-zone.log' -Title 'Route 53 zones'
$zones = Invoke-AwsCli @('route53','list-hosted-zones-by-name','--dns-name',$apex,'--query',"HostedZones[?Name=='$apex.'].[Id,Config.PrivateZone,ResourceRecordSetCount]",'--output','text') -Quiet
Add-Content $log "zones: $zones"
foreach ($line in ($zones -split "`r?`n")) {
  $id = ($line -split '\s+')[0]
  if ($id -like '/hostedzone/*') {
    $ns = Invoke-AwsCli @('route53','get-hosted-zone','--id',$id,'--query','DelegationSet.NameServers','--output','text') -Quiet
    Add-Content $log "$id name servers: $ns"
  }
}
Add-Content $log 'DONE'
Get-Content $log
Read-Host 'Press Enter to close'

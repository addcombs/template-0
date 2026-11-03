# Setup step 4: creates the private S3 bucket that holds the built UI (<app>-ui-<account>),
# with all public access blocked; CloudFront will read it through origin access control (step 5).
# Safe to re-run. Log: logs\ui-bucket.log
. "$PSScriptRoot\common.ps1" -LogName 'ui-bucket.log' -Title 'UI bucket'

$account = Invoke-AwsCli @('sts','get-caller-identity','--query','Account','--output','text')
$bucket = UiBucket $account
Step "account: $account, bucket: $bucket"

if ($null -eq (Invoke-AwsCli @('s3api','head-bucket','--bucket',$bucket) -AllowFail)) {
  Invoke-AwsCli @('s3api','create-bucket','--bucket',$bucket,'--create-bucket-configuration',"LocationConstraint=$awsRegion") | Out-Null
  Step "bucket created: $bucket"
} else { Step "bucket exists: $bucket" }

Invoke-AwsCli @('s3api','put-public-access-block','--bucket',$bucket,'--public-access-block-configuration','BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true') | Out-Null
$block = Invoke-AwsCli @('s3api','get-public-access-block','--bucket',$bucket,'--query','PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]','--output','text')
if ($block -notmatch '^True\s+True\s+True\s+True$') { Fail "public access block not fully on: $block" }
Step 'public access: all four blocks on'
$where = Invoke-AwsCli @('s3api','get-bucket-location','--bucket',$bucket,'--query','LocationConstraint','--output','text')
Step "bucket region: $where"
Step "DONE. Bucket for step 5 (CloudFront origin 1): $bucket.s3.$awsRegion.amazonaws.com"
Read-Host 'Press Enter to close'

# Lets GitHub Actions deploy the app (.github/workflows/ci.yml) without stored AWS keys: an IAM role
# that only pushes to main of this repository (the git origin) can assume through GitHub's OIDC
# provider, allowed only to upload the UI, refresh its CloudFront distribution, apply the theme
# colors to the Cognito sign-in page, and publish new API code to the existing function. The function's settings, including the database login, stay as
# deploy-api.ps1 set them. Safe to re-run: the provider is reused and the role's policies are
# replaced. Afterwards add the printed role ARN to the GitHub repository as the Actions variable
# AWS_DEPLOY_ROLE_ARN. Log: logs\github-deploy-role.log
. "$PSScriptRoot\common.ps1" -LogName 'github-deploy-role.log' -Title 'GitHub deploy role'
$roleName = $names.GitHubDeployRole

$origin = & git -C $root remote get-url origin
if ($origin -notmatch 'github\.com[:/]([^/]+/[^/]+?)(\.git)?$') { Fail "git origin '$origin' is not a GitHub repository." }
$repo = $Matches[1]
# GitHub's tokens name the repository with its owner's and its own IDs, e.g.
# repo:<owner>@<owner id>/<repo>@<repo id>, so the trust policy must too.
try { $info = Invoke-RestMethod "https://api.github.com/repos/$repo" -Headers @{ 'User-Agent' = $app } }
catch { Fail "could not look up $repo on GitHub: $($_.Exception.Message)" }
$subject = "repo:$($info.owner.login)@$($info.owner.id)/$($info.name)@$($info.id):ref:refs/heads/main"
$account = Invoke-AwsCli @('sts','get-caller-identity','--query','Account','--output','text')
Step "repository: $repo, account: $account, token subject: $subject"

# --- GitHub's OIDC provider (one per account, shared by every app) ---
$providerHost = 'token.actions.githubusercontent.com'
$provider = "arn:aws:iam::${account}:oidc-provider/$providerHost"
if ($null -eq (Invoke-AwsCli @('iam','get-open-id-connect-provider','--open-id-connect-provider-arn',$provider) -AllowFail -Quiet)) {
  Invoke-AwsCli @('iam','create-open-id-connect-provider','--url',"https://$providerHost",'--client-id-list','sts.amazonaws.com') | Out-Null
  Step "OIDC provider created: $provider"
} else { Step "OIDC provider exists: $provider" }

# --- role, assumable only by pushes to main ---
$trust = Write-Json (Join-Path $logs 'github-deploy-trust.json') @{
  Version = '2012-10-17'
  Statement = @(@{
    Effect = 'Allow'; Principal = @{ Federated = $provider }; Action = 'sts:AssumeRoleWithWebIdentity'
    Condition = @{ StringEquals = @{ "${providerHost}:aud" = 'sts.amazonaws.com'; "${providerHost}:sub" = $subject } }
  })
}
$roleArn = Invoke-AwsCli @('iam','get-role','--role-name',$roleName,'--query','Role.Arn','--output','text') -AllowFail -Quiet
if (-not $roleArn) {
  $roleArn = Invoke-AwsCli @('iam','create-role','--role-name',$roleName,'--assume-role-policy-document',"file://$trust",
    '--description',"GitHub Actions deploys of $repo",'--query','Role.Arn','--output','text')
  Step "role created: $roleArn"
} else {
  Invoke-AwsCli @('iam','update-assume-role-policy','--role-name',$roleName,'--policy-document',"file://$trust") | Out-Null
  Step "role exists: $roleArn (trust policy updated)"
}

# --- permissions: exactly what the deploy jobs call ---
$distId = Invoke-AwsCli @('cloudfront','list-distributions','--query',"DistributionList.Items[?Aliases.Items && contains(Aliases.Items, '$domain')].Id | [0]",'--output','text')
if (-not $distId -or $distId -eq 'None') { Fail "No CloudFront distribution for $domain. Run scripts\create-cloudfront.ps1 first." }
$uiBucket = UiBucket $account
$function = "arn:aws:lambda:${awsRegion}:${account}:function:$($names.Function)"
$userPool = "arn:aws:cognito-idp:${awsRegion}:${account}:userpool/$((Get-CognitoIds).userPoolId)"
$policy = Write-Json (Join-Path $logs 'github-deploy-policy.json') @{
  Version = '2012-10-17'
  Statement = @(
    @{ Sid = 'UiList'; Effect = 'Allow'; Action = 's3:ListBucket'; Resource = "arn:aws:s3:::$uiBucket" },
    @{ Sid = 'UiWrite'; Effect = 'Allow'; Action = @('s3:PutObject','s3:DeleteObject'); Resource = "arn:aws:s3:::$uiBucket/*" },
    @{ Sid = 'UiRefresh'; Effect = 'Allow'; Action = @('cloudfront:CreateInvalidation','cloudfront:GetInvalidation'); Resource = "arn:aws:cloudfront::${account}:distribution/$distId" },
    @{ Sid = 'FindDistribution'; Effect = 'Allow'; Action = 'cloudfront:ListDistributions'; Resource = '*' },
    @{ Sid = 'LoginBranding'; Effect = 'Allow'; Resource = $userPool
       Action = @('cognito-idp:DescribeManagedLoginBrandingByClient','cognito-idp:UpdateManagedLoginBranding') },
    # Lambda reads the uploaded zip with the caller's permissions.
    @{ Sid = 'ApiUpload'; Effect = 'Allow'; Action = @('s3:PutObject','s3:GetObject'); Resource = "arn:aws:s3:::$(DeployBucket $account)/$($names.DeployKey)" },
    @{ Sid = 'ApiPublish'; Effect = 'Allow'; Resource = @($function, "${function}:*")
       Action = @('lambda:UpdateFunctionCode','lambda:PublishVersion','lambda:UpdateAlias','lambda:GetFunction','lambda:GetFunctionConfiguration') }
  )
}
Invoke-AwsCli @('iam','put-role-policy','--role-name',$roleName,'--policy-name','deploy','--policy-document',"file://$policy") | Out-Null
Step "permissions set: UI bucket $uiBucket, distribution $distId, user pool $userPool, function $($names.Function)"
Step "DONE. In GitHub, $repo > Settings > Secrets and variables > Actions > Variables, add AWS_DEPLOY_ROLE_ARN = $roleArn"
Read-Host 'Press Enter to close'

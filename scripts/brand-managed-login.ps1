# Applies the app's colours to its Cognito managed-login style. config\managed-login-branding.json
# holds the style (app-like neutral backgrounds, light/dark following the visitor's system setting)
# with the theme colours as palette references such as {primary-40} or {secondary-90}; they are
# filled in from the UI's Material palettes (<app>-ui\src\app\theme\generated_theme-colors.scss,
# generated from project.json theme by scripts\start-all.ps1), so the sign-in page matches the app.
# Run scripts\create-cognito-pool.ps1 first.
# Log: logs\managed-login.log (appended); the filled-in style: logs\managed-login-branding-filled.json
. "$PSScriptRoot\common.ps1" -LogName 'managed-login.log' -AppendLog
$settings = Join-Path $config 'managed-login-branding.json'
if (-not (Test-Path $settings)) { Fail 'config\managed-login-branding.json not found.' }
$themeFile = Join-Path $uiDir 'src\app\theme\generated_theme-colors.scss'
if (-not (Test-Path $themeFile)) { Fail 'theme palettes not found. Run scripts\start-all.ps1 to generate them.' }
$theme = Get-Content $themeFile -Raw

# The palettes must come from the colours in project.json, or the sign-in page would get old ones.
$source = [regex]::Match($theme, 'generated from primary: (#\w+), secondary: (#\w+)')
if ($source.Groups[1].Value -ne $project.theme.primary -or $source.Groups[2].Value -ne $project.theme.secondary) {
  Fail "the theme palettes are not from project.json's colours. Run scripts\start-all.ps1 to regenerate them."
}

# Reads each palette block, e.g. `primary: ( 40: #00668a, ... )`, into palette-tone -> rrggbb.
$tones = @{}
foreach ($block in [regex]::Matches($theme, '(?m)^\s+([a-z-]+): \(([^)]*)\)')) {
  foreach ($tone in [regex]::Matches($block.Groups[2].Value, '(\d+): #([0-9a-fA-F]{6})')) {
    $tones["$($block.Groups[1].Value)-$($tone.Groups[1].Value)"] = $tone.Groups[2].Value.ToLowerInvariant()
  }
}
$missing = @()
$style = [regex]::Replace((Get-Content $settings -Raw), '\{([a-z-]+-\d+)\}', {
  param($m)
  $hex = $tones[$m.Groups[1].Value]
  if (-not $hex) { $script:missing += $m.Value; return $m.Value }
  return "${hex}ff"
})
if ($missing) { Fail "unknown palette colours in config\managed-login-branding.json: $(($missing | Sort-Object -Unique) -join ', ')" }
$filled = Join-Path $logs 'managed-login-branding-filled.json'
Write-Utf8 $filled $style
Step "style filled in from primary $($project.theme.primary), secondary $($project.theme.secondary): logs\managed-login-branding-filled.json"

$ids = Get-CognitoIds
$id = Invoke-AwsCli @('cognito-idp','describe-managed-login-branding-by-client','--user-pool-id',$ids.userPoolId,'--client-id',$ids.userPoolClientId,'--query','ManagedLoginBranding.ManagedLoginBrandingId','--output','text')
Invoke-AwsCli @('cognito-idp','update-managed-login-branding','--user-pool-id',$ids.userPoolId,'--managed-login-branding-id',$id,'--settings',"file://$filled",'--query','ManagedLoginBranding.LastModifiedDate','--output','text') | Out-Null
Step "BRANDING DONE: $app colours applied to style $id"
Read-Host 'Press Enter to close'

# Get-ManagedLoginStyle fills config\managed-login-branding.json's palette references, such as
# {primary-40} or {secondary-90}, from the UI's Material palettes, so the Cognito sign-in page
# matches the app. The UI deploy (.github/workflows/ci.yml, PowerShell 7 on Linux) dot-sources it
# and applies the result, so it needs nothing else.
function Get-ManagedLoginStyle([string]$ThemeFile, [string]$SettingsFile, [string]$Primary) {
  $theme = Get-Content $ThemeFile -Raw
  # The palettes must come from the colour in project.json, or the sign-in page would get old ones.
  $source = [regex]::Match($theme, '(?m)generated from primary: (#\w+)\s*$')
  if ($source.Groups[1].Value -ne $Primary) {
    throw "the theme palettes are not from project.json's colour. Run scripts\start-all.ps1 to regenerate them."
  }
  # Reads each palette block, e.g. `primary: ( 40: #00668a, ... )`, into palette-tone -> rrggbb.
  $tones = @{}
  foreach ($block in [regex]::Matches($theme, '(?m)^\s+([a-z-]+): \(([^)]*)\)')) {
    foreach ($tone in [regex]::Matches($block.Groups[2].Value, '(\d+): #([0-9a-fA-F]{6})')) {
      $tones["$($block.Groups[1].Value)-$($tone.Groups[1].Value)"] = $tone.Groups[2].Value.ToLowerInvariant()
    }
  }
  $missing = New-Object System.Collections.Generic.List[string]
  $style = [regex]::Replace((Get-Content $SettingsFile -Raw), '\{([a-z-]+-\d+)\}', {
    param($m)
    $hex = $tones[$m.Groups[1].Value]
    if (-not $hex) { $missing.Add($m.Value); return $m.Value }
    return "${hex}ff"
  })
  if ($missing.Count) { throw "unknown palette colours in config\managed-login-branding.json: $(($missing | Sort-Object -Unique) -join ', ')" }
  return $style
}

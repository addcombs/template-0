# Read-only: lists the build tools the app needs (Java 21, Maven, Node.js/npm), other JDK and Maven
# installs start-all.ps1 could use, and anything already listening on ports 8080 and 4200.
# Log: logs\check-tools.log
. "$PSScriptRoot\common.ps1" -LogName 'check-tools.log' -Title 'tools'

function Section($name, [scriptblock]$body) {
  Add-Content $log "== $name"
  & $body | ForEach-Object { "$_" } | Add-Content $log
}
function Where-Command($name) { (Get-Command $name -All -ErrorAction SilentlyContinue).Source }
# Version commands print to stderr; cmd merges it so PowerShell 5 doesn't wrap it as errors.
function Version($command) { cmd.exe /c "$command 2>&1" }
function Find-Mvn($dir) {
  Get-ChildItem $dir -Recurse -Filter mvn.cmd -ErrorAction SilentlyContinue |
    Where-Object FullName -match '\\bin\\mvn\.cmd$' | ForEach-Object FullName
}

Section 'java' { Where-Command java; Version 'java -version' }
Section "JAVA_HOME=$env:JAVA_HOME" {}
Section 'mvn' { Where-Command mvn }
Section 'node' { Where-Command node; Version 'node -v' }
Section 'npm' { Where-Command npm; Version 'npm -v' }
Section 'jdks' { Get-ChildItem "$env:USERPROFILE\.jdks" -Name -ErrorAction SilentlyContinue }
Section 'maven wrapper dists' { Find-Mvn "$env:USERPROFILE\.m2\wrapper\dists" }
Section 'intellij maven' { Find-Mvn "$env:ProgramFiles\JetBrains"; Find-Mvn "$env:LOCALAPPDATA\Programs" }
Section 'ports' { netstat -ano | Select-String ':(8080|4200)\s' | Select-String 'LISTENING' | ForEach-Object { $_.Line.Trim() } }
Add-Content $log '== done'
Get-Content $log
Read-Host 'Press Enter to close'

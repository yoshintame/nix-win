param(
  [Parameter(Mandatory = $true)][string]$Module,
  [Parameter(Mandatory = $true)][string]$Settings,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Paths
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Module 'PSScriptAnalyzer.psd1')

$findings = foreach ($path in $Paths) {
  Invoke-ScriptAnalyzer -Path $path -Settings $Settings
}
foreach ($finding in $findings) {
  '{0}:{1}: {2} {3}: {4}' -f $finding.ScriptPath, $finding.Line, $finding.Severity, $finding.RuleName, $finding.Message
}
if ($findings) {
  exit 1
}

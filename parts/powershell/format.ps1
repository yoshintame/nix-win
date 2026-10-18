param(
  [Parameter(Mandatory = $true)][string]$Module,
  [Parameter(Mandatory = $true)][string]$Settings,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Paths
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Module 'PSScriptAnalyzer.psd1')

foreach ($path in $Paths) {
  $text = [System.IO.File]::ReadAllText($path)
  $formatted = Invoke-Formatter -ScriptDefinition $text -Settings $Settings
  if ($formatted -cne $text) {
    [System.IO.File]::WriteAllText($path, $formatted)
  }
}

$global:ErrorActionPreference = 'Stop'
$env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
$failed = $false
function Invoke-Step([string]$Label, [scriptblock]$Body) { try { & $Body } catch { Write-Output "FAILED ${Label}: $($_.Exception.Message -replace '\s+', ' ')"; $script:failed = $true } }

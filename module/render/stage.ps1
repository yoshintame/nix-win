$ErrorActionPreference = 'Stop'
$env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')

$root = Join-Path $env:ProgramData 'nix-win'
$administrators = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544'

$acl = New-Object System.Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)
$acl.SetOwner($administrators)
foreach ($grant in @(@('S-1-5-18', 'FullControl'), @('S-1-5-32-544', 'FullControl'), @('S-1-5-32-545', 'ReadAndExecute'))) {
  $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    (New-Object System.Security.Principal.SecurityIdentifier $grant[0]), $grant[1],
    'ContainerInherit,ObjectInherit', 'None', 'Allow')
  $acl.AddAccessRule($rule)
}

function Test-Trusted {
  $current = Get-Acl $root
  $current.AreAccessRulesProtected -and
    $current.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -eq $administrators.Value
}

if ((Test-Path $root) -and -not (Test-Trusted)) {
  icacls $root /setowner '*S-1-5-32-544' /t /c /q | Out-Null
  icacls $root /reset /t /c /q | Out-Null
  Remove-Item $root -Recurse -Force
}
if (-not (Test-Path $root)) {
  [void][System.IO.Directory]::CreateDirectory($root, $acl)
}
if (-not (Test-Trusted)) {
  throw "$root is not owned by Administrators with a protected ACL"
}

$current = Join-Path $root 'current'
if (Test-Path $current) {
  Remove-Item $current -Recurse -Force
}
Copy-Item -LiteralPath $PSScriptRoot -Destination $current -Recurse

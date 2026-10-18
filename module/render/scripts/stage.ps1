param([Parameter(Mandatory = $true)][string]$Root)

$global:ErrorActionPreference = 'Stop'
$env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')

$administrators = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544'

$acl = New-Object System.Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)
$acl.SetOwner($administrators)
foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
  $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    (New-Object System.Security.Principal.SecurityIdentifier $sid), 'FullControl',
    'ContainerInherit,ObjectInherit', 'None', 'Allow')
  $acl.AddAccessRule($rule)
}

$directory = [System.IO.FileAttributes]::Directory
$reparsePoint = [System.IO.FileAttributes]::ReparsePoint

function Get-RootAttributes {
  try {
    [System.IO.File]::GetAttributes($Root)
  } catch [System.IO.FileNotFoundException], [System.IO.DirectoryNotFoundException] {
    $null
  }
}

function Test-Trusted {
  $attributes = Get-RootAttributes
  if ($null -eq $attributes -or ($attributes -band $reparsePoint) -or -not ($attributes -band $directory)) {
    return $false
  }
  $current = Get-Acl -LiteralPath $Root
  $current.AreAccessRulesProtected -and
    $current.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -eq $administrators.Value
}

function Remove-Untrusted {
  $attributes = Get-RootAttributes
  if ($null -eq $attributes) {
    return
  }
  $aside = "$Root-untrusted-$([guid]::NewGuid().ToString('N'))"
  if ($attributes -band $reparsePoint) {
    if ($attributes -band $directory) { [System.IO.Directory]::Delete($Root) } else { [System.IO.File]::Delete($Root) }
  } elseif ($attributes -band $directory) {
    [System.IO.Directory]::Move($Root, $aside)
  } else {
    [System.IO.File]::Move($Root, $aside)
  }
}

if (-not (Test-Trusted)) {
  Remove-Untrusted
  [void][System.IO.Directory]::CreateDirectory($Root, $acl)
  if (-not (Test-Trusted)) {
    throw "$Root is not a directory owned by Administrators with a protected ACL"
  }
}
[System.IO.Directory]::SetAccessControl($Root, $acl)

$current = Join-Path $Root 'current'
if (Test-Path -LiteralPath $current) {
  Remove-Item -LiteralPath $current -Recurse -Force
}
Copy-Item -LiteralPath $PSScriptRoot -Destination $current -Recurse
[void][System.IO.Directory]::CreateDirectory((Join-Path $Root 'pending'))

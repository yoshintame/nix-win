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

$directory = [System.IO.FileAttributes]::Directory
$reparsePoint = [System.IO.FileAttributes]::ReparsePoint

function Get-RootAttributes {
  try {
    [System.IO.File]::GetAttributes($root)
  } catch [System.IO.FileNotFoundException], [System.IO.DirectoryNotFoundException] {
    $null
  }
}

function Test-Trusted {
  $attributes = Get-RootAttributes
  if ($null -eq $attributes -or ($attributes -band $reparsePoint) -or -not ($attributes -band $directory)) {
    return $false
  }
  $current = Get-Acl -LiteralPath $root
  $current.AreAccessRulesProtected -and
    $current.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -eq $administrators.Value
}

$attributes = Get-RootAttributes
if ($null -ne $attributes -and -not (Test-Trusted)) {
  $aside = "$root-untrusted-$([guid]::NewGuid().ToString('N'))"
  if (($attributes -band $reparsePoint) -and ($attributes -band $directory)) {
    [System.IO.Directory]::Delete($root)
  } elseif ($attributes -band $reparsePoint) {
    [System.IO.File]::Delete($root)
  } elseif ($attributes -band $directory) {
    [System.IO.Directory]::Move($root, $aside)
  } else {
    [System.IO.File]::Move($root, $aside)
  }
}
if ($null -eq (Get-RootAttributes)) {
  [void][System.IO.Directory]::CreateDirectory($root, $acl)
}
if (-not (Test-Trusted)) {
  throw "$root is not a directory owned by Administrators with a protected ACL"
}

$current = Join-Path $root 'current'
if (Test-Path -LiteralPath $current) {
  Remove-Item -LiteralPath $current -Recurse -Force
}
Copy-Item -LiteralPath $PSScriptRoot -Destination $current -Recurse

param(
  [Parameter(Mandatory = $true)][ValidateSet('install', 'verify')][string]$Mode,
  [Parameter(Mandatory = $true)][string]$StateDir
)

$global:ErrorActionPreference = 'Stop'
$env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')

$installed = @('0x00000000', '0x8A15002B', '0x8A150061', '0x8A15010D')
$rebootRequired = '0x8A150109'
$family = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe'
$unsafeSettings = @('portablePackageMachineRoot', 'defaultInstallRoot')

function Format-Code([int]$Code) { '0x{0:X8}' -f $Code }

function Write-Status([string]$Text) { [Console]::Error.WriteLine("nix-win: $Text") }

function Get-Winget {
  if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
    throw 'not supported under SYSTEM, which has no App Installer registration'
  }
  $root = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx' -Name PackageRoot).PackageRoot
  $candidates = @(Get-AppxPackage -Name Microsoft.DesktopAppInstaller | Where-Object {
      $_.PackageFamilyName -eq $family -and $_.SignatureKind -eq 'Store' -and -not $_.IsDevelopmentMode
    })
  if ($candidates.Count -ne 1) {
    throw "expected one Store-signed $family registration, found $($candidates.Count)"
  }
  $location = $candidates[0].InstallLocation
  if (-not $location.StartsWith("$root\", [StringComparison]::OrdinalIgnoreCase)) {
    throw "$location is outside $root"
  }
  $winget = Join-Path -Path $location -ChildPath 'winget.exe'
  $signature = Get-AuthenticodeSignature -LiteralPath $winget
  if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notlike 'CN=Microsoft Corporation,*') {
    throw "$winget is not signed by Microsoft"
  }
  $winget
}

function Assert-SafeSetting([string]$Path, [string]$Text) {
  if ($Text -cmatch '(?<!\\)(?:\\\\)*\\u') {
    throw "$Path uses \u escapes, which could hide a setting that points an elevated install at a directory the user controls"
  }
  foreach ($name in $unsafeSettings) {
    if ($Text -match [regex]::Escape($name)) {
      throw "$Path sets $name, which would point an elevated install at a directory the user controls"
    }
  }
}

function Lock-UserSetting([string]$Winget) {
  $file = (& $Winget settings export | ConvertFrom-Json).userSettingsFile
  $lock = [pscustomobject]@{ Paths = @($file, "$file.backup"); Held = @() }
  foreach ($path in $lock.Paths) {
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $lock.Held += $stream
    $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8, $true, 4096, $true)
    Assert-SafeSetting -Path $path -Text $reader.ReadToEnd()
  }
  $lock
}

function Assert-NoNewSetting($Lock) {
  $held = @($Lock.Held | ForEach-Object { $_.Name })
  foreach ($path in $Lock.Paths) {
    if ($held -notcontains $path -and (Test-Path -LiteralPath $path)) {
      throw "$path appeared during the run"
    }
  }
}

function Join-Argument([string[]]$Arguments) {
  ($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
}

function Wait-InstallerIdle([int]$Seconds) {
  $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
  do {
    $mutex = $null
    try {
      if (-not [Threading.Mutex]::TryOpenExisting('Global\_MSIExecute', [Security.AccessControl.MutexRights]::Synchronize, [ref]$mutex)) {
        return $true
      }
      $mutex.Dispose()
    } catch [UnauthorizedAccessException] {
      $null = $_
    }
    Start-Sleep -Seconds 5
  } while ([DateTime]::UtcNow -lt $deadline)
  $false
}

function Install-WingetPackage($Package, [string]$Winget, [string]$Logs) {
  $arguments = @('install', '--id', $Package.Id, '--exact', '--source', $Package.Source, '--scope', 'machine',
    '--silent', '--no-upgrade', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
  if ($Package.Location) { $arguments += @('--location', $Package.Location) }
  if ($Package.InstallerType) { $arguments += @('--installer-type', $Package.InstallerType) }
  $log = Join-Path -Path $Logs -ChildPath "$($Package.Id).log"
  $process = Start-Process -FilePath $Winget -ArgumentList (Join-Argument -Arguments $arguments) -NoNewWindow -PassThru `
    -RedirectStandardOutput $log -RedirectStandardError "$log.err"
  $null = $process.Handle
  if (-not $process.WaitForExit($Package.Timeout * 1000)) {
    $ErrorActionPreference = 'Continue'
    & (Join-Path -Path ([Environment]::SystemDirectory) -ChildPath 'taskkill.exe') /T /F /PID $process.Id 2>&1 | Out-Null
    return [pscustomobject]@{ Ok = $false; Detail = "timeout after $($Package.Timeout) s"; TimedOut = $true }
  }
  $code = Format-Code -Code $process.ExitCode
  if ($code -eq $rebootRequired) {
    return [pscustomobject]@{ Ok = $true; Detail = 'a reboot finishes the install'; TimedOut = $false }
  }
  $ok = $installed -contains $code
  if ($ok) { Repair-PortableAcl -Id $Package.Id }
  [pscustomobject]@{ Ok = $ok; Detail = $code; TimedOut = $false }
}

function Repair-PortableAcl([string]$Id) {
  $root = Join-Path -Path ([Environment]::GetFolderPath('ProgramFiles')) -ChildPath 'WinGet\Packages'
  $icacls = Join-Path -Path ([Environment]::SystemDirectory) -ChildPath 'icacls.exe'
  Get-ChildItem -LiteralPath $root -Directory -Filter "${Id}_*" -ErrorAction SilentlyContinue | ForEach-Object {
    & $icacls $_.FullName /reset /T /C /Q | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls /reset on $($_.FullName) exited with $LASTEXITCODE" }
  }
}

function Test-WingetPackage($Package, [string]$Winget) {
  & $Winget list --id $Package.Id --exact --scope machine --accept-source-agreements --disable-interactivity | Out-Null
  $LASTEXITCODE -eq 0
}

$Packages = Get-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'winget.json') -Raw -Encoding UTF8 | ConvertFrom-Json

try {
  $winget = Get-Winget
} catch {
  Write-Output "FAILED winget: $($_.Exception.Message)"
  exit 1
}

$logs = Join-Path -Path $StateDir -ChildPath 'winget'
$temp = Join-Path -Path $logs -ChildPath 'tmp'
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($elevated) {
  try {
    [void](New-Item -ItemType Directory -Force -Path $temp)
    Get-ChildItem -LiteralPath (Join-Path -Path $temp -ChildPath 'WinGet') -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -ne 'cache' } | Remove-Item -Recurse -Force
    $env:TMP = $temp
    $env:TEMP = $temp
  } catch {
    Write-Output "FAILED winget: $($_.Exception.Message)"
    exit 1
  }
}

if ($Mode -eq 'verify') {
  foreach ($package in $Packages) {
    Write-Output "@@ winget $($package.Index)"
    if (Test-WingetPackage -Package $package -Winget $winget) { Write-Output 'installed' }
  }
  exit 0
}

try {
  if (-not $elevated) { throw 'installing needs an administrator session' }
  $lock = Lock-UserSetting -Winget $winget
} catch {
  Write-Output "FAILED winget: $($_.Exception.Message)"
  exit 1
}

$failed = $false
$stop = $null
try {
  foreach ($package in $Packages) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    if ($stop) {
      $result = [pscustomobject]@{ Ok = $false; Detail = "skipped: $stop"; TimedOut = $false }
    } else {
      try {
        Assert-NoNewSetting -Lock $lock
      } catch {
        $stop = $_.Exception.Message
      }
      if ($stop) {
        $result = [pscustomobject]@{ Ok = $false; Detail = "skipped: $stop"; TimedOut = $false }
      } else {
        try {
          $result = Install-WingetPackage -Package $package -Winget $winget -Logs $logs
        } catch {
          $result = [pscustomobject]@{ Ok = $false; Detail = $_.Exception.Message -replace '\s+', ' '; TimedOut = $false }
        }
      }
    }
    $seconds = [math]::Round($watch.Elapsed.TotalSeconds)
    if ($result.Ok) {
      Write-Status "winget $($package.Id) ok in $seconds s$(if ($result.Detail -notmatch '^0x') { ", $($result.Detail)" })"
    } else {
      Write-Status "winget $($package.Id) failed in $seconds s: $($result.Detail), logs $logs\$($package.Id).log and .log.err"
      Write-Output "FAILED winget $($package.Id): $($result.Detail)"
      $failed = $true
    }
    if ($result.TimedOut -and -not (Wait-InstallerIdle -Seconds $package.Timeout)) {
      $stop = "Windows Installer still busy after $($package.Id) timed out"
    }
  }
} finally {
  $lock.Held | ForEach-Object { $_.Dispose() }
}
if ($failed) { exit 1 }

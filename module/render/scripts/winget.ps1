param(
  [Parameter(Mandatory = $true)][ValidateSet('install', 'verify')][string]$Mode,
  [Parameter(Mandatory = $true)][string]$StateDir
)

$global:ErrorActionPreference = 'Stop'
$env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')

$installed = @('0x00000000', '0x8A15002B', '0x8A150061')
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

function Assert-SafeSetting([string]$Winget) {
  $file = (& $Winget settings export | ConvertFrom-Json).userSettingsFile
  foreach ($candidate in @($file, "$file.backup")) {
    if (-not (Test-Path -LiteralPath $candidate)) { continue }
    $text = Get-Content -LiteralPath $candidate -Raw
    foreach ($name in $unsafeSettings) {
      if ($text -match "`"$name`"") {
        throw "$candidate sets $name, which would point an elevated install at a directory the user controls"
      }
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
    if (-not [Threading.Mutex]::TryOpenExisting('Global\_MSIExecute', [ref]$mutex)) { return $true }
    $mutex.Dispose()
    Start-Sleep -Seconds 5
  } while ([DateTime]::UtcNow -lt $deadline)
  $false
}

function Install-WingetPackage($Package, [string]$Winget, [string]$Logs) {
  $arguments = @('install', '--id', $Package.Id, '--exact', '--source', $Package.Source, '--scope', 'machine',
    '--silent', '--no-upgrade', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
  if ($Package.Location) { $arguments += @('--location', $Package.Location) }
  $log = Join-Path -Path $Logs -ChildPath "$($Package.Id).log"
  $process = Start-Process -FilePath $Winget -ArgumentList (Join-Argument -Arguments $arguments) -NoNewWindow -PassThru `
    -RedirectStandardOutput $log -RedirectStandardError "$log.err"
  $null = $process.Handle
  if (-not $process.WaitForExit($Package.Timeout * 1000)) {
    & (Join-Path -Path ([Environment]::SystemDirectory) -ChildPath 'taskkill.exe') /T /F /PID $process.Id | Out-Null
    return [pscustomobject]@{ Ok = $false; Detail = "timeout after $($Package.Timeout) s"; TimedOut = $true }
  }
  $code = Format-Code -Code $process.ExitCode
  [pscustomobject]@{ Ok = $installed -contains $code; Detail = $code; TimedOut = $false }
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

if ($Mode -eq 'verify') {
  foreach ($package in $Packages) {
    Write-Output "@@ winget $($package.Index)"
    if (Test-WingetPackage -Package $package -Winget $winget) { Write-Output 'installed' }
  }
  exit 0
}

$logs = Join-Path -Path $StateDir -ChildPath 'winget'
$temp = Join-Path -Path $logs -ChildPath 'tmp'
try {
  [void](New-Item -ItemType Directory -Force -Path $temp)
  $env:TMP = $temp
  $env:TEMP = $temp
  Assert-SafeSetting -Winget $winget
} catch {
  Write-Output "FAILED winget: $($_.Exception.Message)"
  exit 1
}

$failed = $false
$busy = $null
foreach ($package in $Packages) {
  $watch = [Diagnostics.Stopwatch]::StartNew()
  if ($busy) {
    $result = [pscustomobject]@{ Ok = $false; Detail = "skipped, Windows Installer still busy after $busy timed out"; TimedOut = $false }
  } else {
    try {
      $result = Install-WingetPackage -Package $package -Winget $winget -Logs $logs
    } catch {
      $result = [pscustomobject]@{ Ok = $false; Detail = $_.Exception.Message -replace '\s+', ' '; TimedOut = $false }
    }
  }
  $seconds = [math]::Round($watch.Elapsed.TotalSeconds)
  if ($result.Ok) {
    Write-Status "winget $($package.Id) ok in $seconds s"
  } else {
    Write-Status "winget $($package.Id) failed in $seconds s: $($result.Detail), logs $logs\$($package.Id).log and .log.err"
    Write-Output "FAILED winget $($package.Id): $($result.Detail)"
    $failed = $true
  }
  if ($result.TimedOut -and -not (Wait-InstallerIdle -Seconds $package.Timeout)) { $busy = $package.Id }
}
if ($failed) { exit 1 }

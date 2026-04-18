param(
  [Parameter(Mandatory = $true)][string]$SourceRoot
)

$ErrorActionPreference = 'Stop'

function Assert-Administrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Administrator privileges are required.'
  }
}

function Copy-Tree {
  param(
    [Parameter(Mandatory = $true)][string]$From,
    [Parameter(Mandatory = $true)][string]$To
  )

  New-Item -ItemType Directory -Force -Path $To | Out-Null
  $logPath = Join-Path $env:TEMP ("risco-gateway-copy-" + [guid]::NewGuid().ToString("N") + ".log")
  $null = & robocopy.exe $From $To /MIR /NFL /NDL /NJH /NJS /NP /LOG:$logPath
  if ($LASTEXITCODE -gt 7) {
    throw "robocopy failed with exit code $LASTEXITCODE"
  }
  Remove-Item $logPath -Force -ErrorAction SilentlyContinue
}

Assert-Administrator

$installRoot = Join-Path $env:ProgramFiles 'RiscoGateway'
$dataRoot = Join-Path $env:ProgramData 'RiscoGateway'
$dataDir = Join-Path $dataRoot 'data'
$logsDir = Join-Path $dataRoot 'logs'
$serviceExe = Join-Path $installRoot 'windows\RiscoGatewayService.exe'
$defaultConfig = Join-Path $installRoot 'config.default.json'
$configPath = Join-Path $dataDir 'config.json'
$runKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
$uninstallKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\RiscoGateway'
$trayScript = Join-Path $installRoot 'windows\tray-monitor.ps1'
$syncScript = Join-Path $installRoot 'windows\sync-firewall-rules.ps1'

if (Test-Path $serviceExe) {
  try { & $serviceExe stop | Out-Null } catch {}
  try { & $serviceExe uninstall | Out-Null } catch {}
}

Copy-Tree -From $SourceRoot -To $installRoot
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

if (-not (Test-Path $configPath)) {
  Copy-Item $defaultConfig $configPath -Force
}

$pkg = Get-Content (Join-Path $installRoot 'package.json') -Raw | ConvertFrom-Json
$trayCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $trayScript + '"'

New-Item -Path $uninstallKey -Force | Out-Null
Set-ItemProperty -Path $uninstallKey -Name 'DisplayName' -Value 'Risco Gateway'
Set-ItemProperty -Path $uninstallKey -Name 'DisplayVersion' -Value $pkg.version
Set-ItemProperty -Path $uninstallKey -Name 'Publisher' -Value 'Jaime Acosta'
Set-ItemProperty -Path $uninstallKey -Name 'InstallLocation' -Value $installRoot
Set-ItemProperty -Path $uninstallKey -Name 'NoModify' -Value 1 -Type DWord
Set-ItemProperty -Path $uninstallKey -Name 'NoRepair' -Value 1 -Type DWord
Set-ItemProperty -Path $uninstallKey -Name 'UninstallString' -Value ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $installRoot 'windows\uninstall-gateway.ps1') + '"')

Set-ItemProperty -Path $runKey -Name 'RiscoGatewayTray' -Value $trayCommand -Type String

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $syncScript -AppRoot $installRoot -DataRoot $dataRoot
& $serviceExe install
& $serviceExe start
Start-Sleep -Seconds 5

$service = Get-Service RiscoGateway -ErrorAction Stop
if ($service.Status -ne 'Running') {
  $errLog = Join-Path $logsDir 'RiscoGatewayService.err.log'
  if (Test-Path $errLog) {
    Write-Host 'Service failed to remain running. Last error log lines:' -ForegroundColor Red
    Get-Content $errLog -Tail 40
  }
  throw 'RiscoGateway service did not stay running after installation.'
}

Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $trayScript) -WindowStyle Hidden

Write-Host "Risco Gateway installed in $installRoot"

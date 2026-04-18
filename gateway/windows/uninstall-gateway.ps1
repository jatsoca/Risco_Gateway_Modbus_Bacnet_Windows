param(
  [switch]$RemoveData
)

$ErrorActionPreference = 'Stop'

function Assert-Administrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Administrator privileges are required.'
  }
}

Assert-Administrator

$installRoot = Join-Path $env:ProgramFiles 'RiscoGateway'
$dataRoot = Join-Path $env:ProgramData 'RiscoGateway'
$serviceExe = Join-Path $installRoot 'windows\RiscoGatewayService.exe'
$runKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
$uninstallKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\RiscoGateway'

if (Test-Path $serviceExe) {
  try { & $serviceExe stop | Out-Null } catch {}
  try { & $serviceExe uninstall | Out-Null } catch {}
}

foreach ($ruleName in @('RiscoGateway-Web', 'RiscoGateway-Modbus')) {
  Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
}

Remove-ItemProperty -Path $runKey -Name 'RiscoGatewayTray' -ErrorAction SilentlyContinue
Remove-Item -Path $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue

if (Test-Path $installRoot) {
  Remove-Item -LiteralPath $installRoot -Recurse -Force
}

if ($RemoveData -and (Test-Path $dataRoot)) {
  Remove-Item -LiteralPath $dataRoot -Recurse -Force
}

Write-Host 'Risco Gateway uninstalled.'

param(
  [Parameter(Mandatory = $true)][string]$AppRoot,
  [Parameter(Mandatory = $true)][string]$DataRoot
)

$ErrorActionPreference = 'Stop'

function Get-ActiveConfig {
  $configPath = Join-Path $DataRoot 'data\config.json'
  $defaultPath = Join-Path $AppRoot 'config.default.json'

  if (Test-Path $configPath) {
    return Get-Content $configPath -Raw | ConvertFrom-Json
  }
  if (Test-Path $defaultPath) {
    return Get-Content $defaultPath -Raw | ConvertFrom-Json
  }
  throw 'No configuration file available for firewall synchronization.'
}

$config = Get-ActiveConfig
$rules = @('RiscoGateway-Web', 'RiscoGateway-Modbus')

foreach ($ruleName in $rules) {
  Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
}

if ($config.web.enable -ne $false -and $config.web.http_port) {
  New-NetFirewallRule -DisplayName 'RiscoGateway-Web' `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalPort ([int]$config.web.http_port) `
    -Profile Any | Out-Null
}

if ($config.modbus.enable -ne $false -and $config.modbus.port) {
  New-NetFirewallRule -DisplayName 'RiscoGateway-Modbus' `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalPort ([int]$config.modbus.port) `
    -Profile Any | Out-Null
}

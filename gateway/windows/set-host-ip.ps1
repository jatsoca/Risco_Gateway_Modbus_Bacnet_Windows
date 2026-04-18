param(
  [Parameter(Mandatory = $true)][string]$Ip,
  [Parameter(Mandatory = $true)][int]$Cidr,
  [Parameter(Mandatory = $true)][string]$Gateway,
  [string]$InterfaceAlias
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

if (-not $InterfaceAlias) {
  $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface } | Select-Object -First 1
  if (-not $adapter) {
    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
  }
  if (-not $adapter) {
    throw 'No active network adapter was found.'
  }
  $InterfaceAlias = $adapter.Name
}

Set-NetIPInterface -InterfaceAlias $InterfaceAlias -Dhcp Disabled -ErrorAction SilentlyContinue | Out-Null

Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.IPAddress -ne '127.0.0.1' } |
  Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

Get-NetRoute -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' } |
  Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

Start-Sleep -Seconds 1

New-NetIPAddress `
  -InterfaceAlias $InterfaceAlias `
  -IPAddress $Ip `
  -PrefixLength $Cidr `
  -DefaultGateway $Gateway | Out-Null

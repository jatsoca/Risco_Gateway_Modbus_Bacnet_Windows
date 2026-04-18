$ErrorActionPreference = 'SilentlyContinue'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$installRoot = Join-Path $env:ProgramFiles 'RiscoGateway'
$dataRoot = Join-Path $env:ProgramData 'RiscoGateway'
$configPath = Join-Path $dataRoot 'data\config.json'
$defaultConfigPath = Join-Path $installRoot 'config.default.json'
$serviceName = 'RiscoGateway'

function Get-WebPort {
  try {
    $path = if (Test-Path $configPath) { $configPath } else { $defaultConfigPath }
    if (-not (Test-Path $path)) { return 1001 }
    $config = Get-Content $path -Raw | ConvertFrom-Json
    if ($config.web.http_port) { return [int]$config.web.http_port }
  } catch {
  }
  return 1001
}

function Test-GatewayHealth {
  param([int]$Port)
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri ("http://127.0.0.1:{0}/health" -f $Port) -TimeoutSec 3
    return $response.StatusCode -eq 200
  } catch {
    return $false
  }
}

function Update-NotifyState {
  $port = Get-WebPort
  $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

  if (-not $service) {
    $notify.Icon = [System.Drawing.SystemIcons]::Error
    $notify.Text = 'Risco Gateway sin servicio'
    return
  }

  if ($service.Status -eq 'Running' -and (Test-GatewayHealth -Port $port)) {
    $notify.Icon = [System.Drawing.SystemIcons]::Information
    $notify.Text = 'Risco Gateway operativo'
    return
  }

  if ($service.Status -eq 'Running') {
    $notify.Icon = [System.Drawing.SystemIcons]::Warning
    $notify.Text = 'Risco Gateway sin respuesta web'
    return
  }

  $notify.Icon = [System.Drawing.SystemIcons]::Error
  $notify.Text = 'Risco Gateway detenido'
}

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Visible = $true
$notify.Icon = [System.Drawing.SystemIcons]::Application
$notify.Text = 'Risco Gateway'

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$openDashboard = $menu.Items.Add('Abrir dashboard')
$openConfig = $menu.Items.Add('Abrir configuracion')
$restartService = $menu.Items.Add('Reiniciar servicio')
$menu.Items.Add('-') | Out-Null
$exitMonitor = $menu.Items.Add('Salir del monitor')

$openDashboard.Add_Click({
  $port = Get-WebPort
  Start-Process ("http://127.0.0.1:{0}/" -f $port) | Out-Null
})

$openConfig.Add_Click({
  $port = Get-WebPort
  Start-Process ("http://127.0.0.1:{0}/config" -f $port) | Out-Null
})

$restartService.Add_Click({
  Restart-Service -Name $serviceName -Force
})

$exitMonitor.Add_Click({
  $timer.Stop()
  $notify.Visible = $false
  $notify.Dispose()
  [System.Windows.Forms.Application]::Exit()
})

$notify.ContextMenuStrip = $menu
$notify.Add_DoubleClick({
  $port = Get-WebPort
  Start-Process ("http://127.0.0.1:{0}/" -f $port) | Out-Null
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000
$timer.Add_Tick({ Update-NotifyState })
$timer.Start()

Update-NotifyState
[System.Windows.Forms.Application]::Run()

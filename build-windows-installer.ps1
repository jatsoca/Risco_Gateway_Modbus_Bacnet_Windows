$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$bridgeSource = Join-Path $repoRoot 'bridge'
$appSource = Join-Path $repoRoot 'gateway'
$runtimeSource = Join-Path $repoRoot 'runtime\config.default.json'
$buildRoot = Join-Path $repoRoot 'build\windows-installer'
$packageRoot = Join-Path $buildRoot 'package'
$payloadApp = Join-Path $packageRoot 'app'
$payloadZip = Join-Path $buildRoot 'payload.zip'
$bootstrapScript = Join-Path $buildRoot 'bootstrap-install.ps1'
$installCmd = Join-Path $buildRoot 'install.cmd'
$sedPath = Join-Path $buildRoot 'installer.sed'
$targetExe = Join-Path $buildRoot 'RiscoGateway-Windows-Installer.exe'

Push-Location $bridgeSource
npm install
npm run build
Pop-Location

Push-Location $appSource
npm install
npm run build
Pop-Location

Remove-Item $buildRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $payloadApp | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $payloadApp 'windows') | Out-Null

foreach ($dirName in @('dist', 'public', 'node_modules', 'windows')) {
  $sourceDir = Join-Path $appSource $dirName
  $targetDir = Join-Path $payloadApp $dirName
  $robocopyLog = Join-Path $buildRoot ("robocopy-$dirName.log")
  $null = & robocopy.exe $sourceDir $targetDir /MIR /NFL /NDL /NJH /NJS /NP /LOG:$robocopyLog
  if ($LASTEXITCODE -gt 7) {
    throw "robocopy failed for $dirName with exit code $LASTEXITCODE"
  }
}

Copy-Item $runtimeSource (Join-Path $payloadApp 'config.default.json') -Force
foreach ($fileName in @('package.json', 'LICENSE')) {
  Copy-Item (Join-Path $appSource $fileName) (Join-Path $payloadApp $fileName) -Force
}

$bridgeTarget = Join-Path $payloadApp 'node_modules\@jatsoca\risco-bridge'
if (Test-Path $bridgeTarget) {
  Remove-Item -LiteralPath $bridgeTarget -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $bridgeTarget | Out-Null
Copy-Item (Join-Path $bridgeSource 'package.json') (Join-Path $bridgeTarget 'package.json') -Force
Copy-Item (Join-Path $bridgeSource 'LICENSE') (Join-Path $bridgeTarget 'LICENSE') -Force
Copy-Item (Join-Path $bridgeSource 'dist') (Join-Path $bridgeTarget 'dist') -Recurse -Force

$nodeSource = (Get-Command node -ErrorAction Stop).Source
Copy-Item $nodeSource (Join-Path $payloadApp 'node.exe') -Force
$winswUri = 'https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe'
Invoke-WebRequest -Uri $winswUri -OutFile (Join-Path $payloadApp 'windows\RiscoGatewayService.exe')

Compress-Archive -Path $packageRoot\* -DestinationPath $payloadZip -CompressionLevel Optimal

$bootstrapContent = @'
$ErrorActionPreference = "Stop"
$tempRoot = Join-Path $env:TEMP ("RiscoGatewayInstaller_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
Expand-Archive -Path (Join-Path $PSScriptRoot "payload.zip") -DestinationPath $tempRoot -Force
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tempRoot "app\windows\install-gateway.ps1") -SourceRoot (Join-Path $tempRoot "app")
'@
Set-Content -Path $bootstrapScript -Value $bootstrapContent -Encoding ASCII

$installCmdContent = @'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap-install.ps1"
'@
Set-Content -Path $installCmd -Value $installCmdContent -Encoding ASCII

$sedContent = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=0
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=
DisplayLicense=
FinishMessage=Instalacion completada.
TargetName=$targetExe
FriendlyName=Risco Gateway Windows Installer
AppLaunched=cmd.exe /c install.cmd
PostInstallCmd=<None>
AdminQuietInstCmd=cmd.exe /c install.cmd
UserQuietInstCmd=cmd.exe /c install.cmd
SourceFiles=SourceFiles

[Strings]
FILE0="payload.zip"
FILE1="bootstrap-install.ps1"
FILE2="install.cmd"

[SourceFiles]
SourceFiles0=$buildRoot

[SourceFiles0]
%FILE0%=
%FILE1%=
%FILE2%=
"@
Set-Content -Path $sedPath -Value $sedContent -Encoding ASCII

& iexpress.exe /N /Q /M $sedPath | Out-Null

if (-not (Test-Path $targetExe)) {
  throw 'IExpress did not generate the installer executable.'
}

Write-Host "Installer generated at: $targetExe"

# Risco Gateway Modbus Windows

Gateway para paneles RISCO que corre en Windows y expone:

- Dashboard web de monitoreo y control.
- Modbus TCP para integracion local.
- BACnet/IP opcional para integracion BMS.
- Configuracion web del panel y del gateway.
- Paginas web de diagnostico, Modbus, BACnet y debug.
- Servicio Windows con arranque automatico.
- Testigo en bandeja del sistema.

El core del bridge con el panel y la logica general del gateway se mantienen. Esta version adapta el runtime, la instalacion y la operacion para Windows Server y Windows 11.

## Objetivo operativo

El equipo Windows queda dentro de la misma red IP local donde estan:

- el panel RISCO
- el cliente que consume Modbus TCP
- los equipos que abren el dashboard y la pagina de configuracion

El gateway:

- se conecta por TCP/IP al panel RISCO
- publica estados y control por Modbus TCP
- publica estados por BACnet/IP si el modulo esta habilitado
- expone dashboard, login y configuracion web
- arranca como servicio al iniciar Windows

## Arquitectura

```text
Risco_Gateway_Modbus_Windows/
|- bridge/                    # Nucleo de comunicacion con el panel RISCO
|- gateway/                   # Runtime web, auth, config y servidor Modbus TCP
|- gateway/windows/           # Servicio WinSW, firewall, tray monitor e instalacion
|- runtime/                   # Configuracion versionada y datos de runtime en desarrollo
|- build-windows-installer.ps1
|- README.md
`- LICENSE
```

## Instalador

El instalador generado queda en:

```text
build/windows-installer/RiscoGateway-Windows-Installer.exe
```

Para regenerarlo:

```powershell
powershell -ExecutionPolicy Bypass -File .\build-windows-installer.ps1
```

Ese proceso:

1. instala dependencias
2. compila `bridge`
3. compila `gateway`
4. arma el payload Windows
5. descarga WinSW
6. genera el `.exe`

## Comportamiento en Windows

- Servicio Windows: `RiscoGateway`
- Carpeta de instalacion: `%ProgramFiles%\RiscoGateway`
- Datos persistentes: `%ProgramData%\RiscoGateway`
- Configuracion activa: `%ProgramData%\RiscoGateway\data\config.json`
- Logs del servicio: `%ProgramData%\RiscoGateway\logs`
- Monitor de bandeja: arranca al iniciar sesion

La desinstalacion elimina solo componentes del gateway:

- servicio
- reglas de firewall del gateway
- entrada de autoarranque del monitor
- instalacion en `Program Files`

## Credenciales iniciales

- usuario: `admin`
- contrasena: `Admin123`

Se recomienda cambiar la contrasena despues del primer ingreso.

## Configuracion web

Desde `/config` puedes ajustar:

- IP y puerto del panel
- password e ID del panel
- modo de conexion `direct` o `proxy`
- watchdog y log de comandos
- puerto web y ruta WebSocket
- host y puerto Modbus TCP
- BACnet/IP desde `/bacnet`
- nivel de log y heartbeat
- interface alias del host Windows
- estrategia final de comando para particiones de dos digitos: `ARMP=N` y `DISARMP=N`

## Endpoints principales

- dashboard: `http://IP_DEL_PC:1001/`
- configuracion: `http://IP_DEL_PC:1001/config`
- diagnostico: `http://IP_DEL_PC:1001/diagnostics`
- mapa Modbus: `http://IP_DEL_PC:1001/modbus`
- BACnet/IP: `http://IP_DEL_PC:1001/bacnet`
- debug: `http://IP_DEL_PC:1001/debug`
- health: `http://IP_DEL_PC:1001/health`
- Modbus TCP: puerto `502`
- BACnet/IP: puerto UDP `47808` cuando esta habilitado

## Mapas BMS

Modbus TCP:

- Holding registers `1-32`: particiones. `0=disarmed`, `1=armed`, `2=triggered`, `3=ready`, `4=not ready`.
- Holding registers `33-544`: zonas. `0=closed`, `1=open`, `2=bypass`.
- Discrete inputs `1-32`: particion en alarma.
- Discrete inputs `33-544`: zona abierta.

BACnet/IP:

- Device: instancia configurable, default `432001`.
- Analog Value `1-32`: mismo valor de particiones que Modbus.
- Analog Value `33-544`: mismo valor de zonas que Modbus.
- Binary Value `1-32`: alarma de particion.
- Binary Value `33-544`: zona abierta.
- Escritura BACnet queda bloqueada por defecto. Al habilitarla, AV `1-32` acepta `0=desarmar` y `1=armar total`; AV `33-544` acepta `0=normal` y `2=bypass`.

## Desarrollo local

Compilar bridge:

```powershell
cd .\bridge
npm install
npm run build
```

Compilar gateway:

```powershell
cd ..\gateway
npm install
npm run build
```

Ejecutar localmente sin instalar el servicio:

```powershell
cd .\gateway
$env:RISCO_BASE_DIR = "$PWD\\runtime-data"
node .\dist\main.js
```

## Instalacion manual sin el .exe

Si ya tienes el runtime compilado y quieres instalar manualmente:

```powershell
cd .\gateway\windows
powershell -ExecutionPolicy Bypass -File .\install-gateway.ps1 -SourceRoot C:\ruta\al\runtime\gateway
```

## Desinstalacion manual

```powershell
cd "%ProgramFiles%\RiscoGateway\windows"
powershell -ExecutionPolicy Bypass -File .\uninstall-gateway.ps1
```

Para borrar tambien los datos persistentes:

```powershell
cd "%ProgramFiles%\RiscoGateway\windows"
powershell -ExecutionPolicy Bypass -File .\uninstall-gateway.ps1 -RemoveData
```

## Produccion

Para dejarlo estable en campo:

- usa IP fija para el PC y para el panel
- valida los puertos HTTP y Modbus antes de entregar
- cambia la clave admin despues de instalar
- prueba armado, desarmado, bypass y lectura Modbus
- conserva respaldo de `config.json` antes de actualizar

## Notas tecnicas

- No usa `serialport`
- No usa Docker
- El reinicio controlado del gateway se hace por salida supervisada del servicio
- El core del bridge y la logica de armado, bypass, estados y Modbus no cambian

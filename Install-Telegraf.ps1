param (
    [string]$password
)

if (-not $password -and $args.Length -gt 0) {
    $password = $args[0]
}

Write-Host "Script para la instalación del agente de Telegraf" -ForegroundColor Green
Write-Host "######################################################################" -ForegroundColor Yellow

###############################################################################
# 1. Comprobación de permisos de Administrador
###############################################################################

Write-Host "1.- Comprobando permisos de Administrador"
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Permisos insuficientes para ejecutar este script. Ejecute PowerShell como administrador."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
    Exit 1
}
Write-Host "- Permisos correctos, continuando..." -ForegroundColor Green

###############################################################################
# 2. Comprobación y eliminación del servicio Telegraf
###############################################################################

$serviceName = "telegraf"
Write-Host "2.- Comprobando si existe el servicio '$serviceName'"

$existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($existingService) {
    if ($existingService.Status -eq "Running") {
        Write-Host "- El servicio Telegraf está en ejecución. Deteniéndolo..."
        Stop-Service -Name $serviceName -Force
        Start-Sleep -Seconds 3
    }
    Write-Host "- Eliminando el servicio Telegraf..."
    sc.exe delete $serviceName | Out-Null
    Start-Sleep -Seconds 1
    Write-Host "- Servicio Telegraf eliminado." -ForegroundColor Green
} else {
    Write-Host "- El servicio Telegraf no está instalado." -ForegroundColor DarkYellow
}

###############################################################################
# 3. Comprobación y eliminación del directorio de instalación
###############################################################################

$destino = "C:\Program Files\Telegraf"
Write-Host "3.- Comprobando si existe el directorio '$destino'"

if (Test-Path -Path $destino -PathType Container) {
    Write-Host "- Eliminando directorio Telegraf y su contenido..."
    try {
        Remove-Item -Path $destino -Recurse -Force -ErrorAction Stop
        Write-Host "- Directorio eliminado correctamente." -ForegroundColor Green
    } catch {
        Write-Warning "No se pudo eliminar el directorio '$destino'. Verifica permisos o bloqueos."
        Exit 1
    }
} else {
    Write-Host "- El directorio no existe." -ForegroundColor DarkYellow
}

# Crear el nuevo directorio
New-Item -Path $destino -ItemType Directory -Force | Out-Null
Write-Host "- Directorio creado: $destino" -ForegroundColor Green

###############################################################################
# 4. Descarga e instalación del agente Telegraf
###############################################################################

$zipPath = Join-Path -Path $destino -ChildPath "telegraf.zip"
$downloadUrl = "https://dl.influxdata.com/telegraf/releases/telegraf-1.35.3_windows_amd64.zip"

Write-Host "4.- Descargando agente Telegraf desde $downloadUrl"
Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing

Expand-Archive -Path $zipPath -DestinationPath $destino
Move-Item -Path (Join-Path $destino "telegraf-1.35.3\telegraf.*") -Destination $destino
Remove-Item -Path $zipPath
Remove-Item -Path (Join-Path $destino "telegraf-1.35.3") -Recurse -Force
Remove-Item -Path (Join-Path $destino "telegraf.conf") -Force -ErrorAction SilentlyContinue

###############################################################################
# 5. Crear directorio telegraf.d
###############################################################################

$telegrafD = Join-Path $destino "telegraf.d"
New-Item -Path $telegrafD -ItemType Directory -Force | Out-Null
Write-Host "- Directorio telegraf.d creado." -ForegroundColor Green

###############################################################################
# 6. Determinar nombre de organización
###############################################################################

$domainName = $env:USERDNSDOMAIN
if ($domainName -and $domainName -ne "") {
    $organizationName = $domainName
    Write-Host "- Nombre de dominio detectado: $domainName" -ForegroundColor Green
} else {
    $organizationName = Read-Host "- Equipo fuera de dominio, introduce el nombre del cliente (Ej: HSCALIU o HGASOC)"
}

$confContent = @"
[global_tags]
  organization = "$organizationName"
"@

Set-Content -Path (Join-Path $telegrafD "organization.conf") -Value $confContent
Write-Host "- Archivo organization.conf generado." -ForegroundColor Green

###############################################################################
# 7. Configurar salida hacia InfluxDB
###############################################################################

if (-not $password) {
    $password = Read-Host "- Introduce el password de la BBDD"
}

$outputsContent = @"
[[outputs.influxdb]]
   urls = ["https://metrics.3digits.es:8086"]
   database = "telegraf"
   username = "metrics"
   password = "$password"
   timeout = "10s"
"@

Set-Content -Path (Join-Path $telegrafD "outputs.conf") -Value $outputsContent -Encoding UTF8
Write-Host "- Archivo outputs.conf generado con éxito." -ForegroundColor Green

###############################################################################
# 8. Registro e inicio del servicio Telegraf
###############################################################################

$rutaExe = Join-Path $destino "telegraf.exe"

cd $destino
.\telegraf.exe --service install --config https://raw.githubusercontent.com/3digitsSistemas/telegraf/main/telegraf.conf --config-directory "$telegrafD"

Write-Host "- Servicio Telegraf instalado." -ForegroundColor Green
Start-Service -Name "telegraf"
Start-Sleep -Seconds 5

$estado = Get-Service -Name $serviceName
if ($estado.Status -eq "Running") {
    Write-Host "- Servicio Telegraf iniciado correctamente." -ForegroundColor Green
} else {
    Write-Warning "¡El servicio Telegraf no se ha iniciado correctamente!"
}

###############################################################################
# 9. Configuración de recuperación automática
###############################################################################

sc.exe failure "telegraf" reset=0 actions=restart/60000/restart/60000/restart/60000 | Out-Null
sc.exe config "telegraf" start=delayed-auto | Out-Null
Write-Host "- Recuperación automática del servicio configurada." -ForegroundColor Green

###############################################################################
# Fin del script
###############################################################################

Write-Host "######################################################################" -ForegroundColor Yellow
Write-Host -NoNewLine 'Pulsa una tecla para continuar...';
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
Exit 0

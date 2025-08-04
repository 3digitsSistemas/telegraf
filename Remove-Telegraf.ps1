Write-Host "Script de limpieza previa para instalación de Telegraf" -ForegroundColor Cyan
Write-Host "######################################################################" -ForegroundColor Yellow

###############################################################################
# 1. Comprobación de permisos de Administrador
###############################################################################
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Este script requiere permisos de administrador. Ejecútalo como administrador."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
    Exit 1
}

###############################################################################
# 2. Eliminación del servicio Telegraf si existe
###############################################################################
$serviceName = "telegraf"
$existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($existingService) {
    Write-Host "→ Servicio Telegraf detectado."

    if ($existingService.Status -eq "Running") {
        Write-Host "- Deteniendo servicio..."
        Stop-Service -Name $serviceName -Force
        Start-Sleep -Seconds 2
    }

    Write-Host "- Eliminando servicio..."
    sc.exe delete $serviceName | Out-Null
    Start-Sleep -Seconds 1
    Write-Host "- Servicio eliminado correctamente." -ForegroundColor Green
} else {
    Write-Host "→ Servicio Telegraf no encontrado." -ForegroundColor DarkYellow
}

###############################################################################
# 3. Eliminación del directorio Telegraf si existe
###############################################################################
$installPath = "C:\Program Files\Telegraf"

if (Test-Path -Path $installPath -PathType Container) {
    Write-Host "→ Eliminando directorio Telegraf..."
    try {
        Remove-Item -Path $installPath -Recurse -Force -ErrorAction Stop
        Write-Host "- Directorio eliminado correctamente." -ForegroundColor Green
    } catch {
        Write-Warning "No se pudo eliminar el directorio '$installPath'. Puede estar en uso o protegido."
        Exit 1
    }
} else {
    Write-Host "→ El directorio Telegraf no existe." -ForegroundColor DarkYellow
}

Write-Host "######################################################################" -ForegroundColor Yellow
Write-Host "Tareas completadas. Telegraf eliminado del sistema." -ForegroundColor Cyan
Write-Host -NoNewLine 'Pulsa una tecla para salir...';
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');

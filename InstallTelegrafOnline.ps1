Write-Host "Iniciando Script para la instalación del agente de Telegraft" -ForegroundColor Green
Write-Host "---------------------------" -ForegroundColor Yellow
Write-Host "Comprobando permisos de Administrador" -ForegroundColor Green

if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Permisos insuficientes para ejecutar este script. Ejecute el script de PowerShell como administrador."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
    Exit 1
}

Write-Host "Permisos correctos, iniciando la instalación del agente de Telegraf" -ForegroundColor Green

# Comprobar si el servicio "telegraf" existe
$serviceName = "telegraf"
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($service) {
    # Detener el servicio si está en ejecución
    if ($service.Status -eq "Running") {
        Stop-Service -Name $serviceName -Force
        Start-Sleep -Seconds 5
        Write-Host "Servicio Telegraf detenido." -ForegroundColor Green
    }

    # Eliminar el servicio
    sc.exe delete $serviceName
    Write-Host "Servicio Telegraf eliminado." -ForegroundColor Green
}

# Define el directorio de destino
$destino = "C:\Program Files\Telegraf"

# Verificar si el directorio de destino existe y eliminarlo con todo su contenido si es así
if (Test-Path -Path $destino -PathType Container) {
    Remove-Item -Path $destino -Recurse -Force
    Write-Host "Directorio $destino eliminado con todo su contenido." -ForegroundColor Green
}

# Crear el directorio de destino
New-Item -Path $destino -ItemType Directory
Write-Host "Directorio $destino creado." -ForegroundColor Green

# Crear el directorio telegraf.d en la carpeta de destino
$telegrafD = Join-Path -Path $destino -ChildPath "telegraf.d"
New-Item -Path $telegrafD -ItemType Directory
Write-Host "El directorio telegraf.d se ha creado en $destino." -ForegroundColor Green

# Descarga telegraf en el directorio de destino
$zipPath = Join-Path -Path $destino -ChildPath "telegraf-1.30.3_windows_amd64.zip"
wget https://dl.influxdata.com/telegraf/releases/telegraf-1.30.3_windows_amd64.zip -UseBasicParsing -OutFile $zipPath

# Descomprimir el archivo en el directorio de destino
Expand-Archive -Path $zipPath -DestinationPath $destino

# Mover los archivos telegraf.* del directorio descomprimido al directorio de destino
Move-Item -Path (Join-Path -Path $destino -ChildPath "telegraf-1.30.3\telegraf.*") -Destination $destino

# Eliminar el archivo ZIP y el directorio descomprimido
Remove-Item -Path $zipPath
Remove-Item -Path (Join-Path -Path $destino -ChildPath "telegraf-1.30.3") -Recurse -Force

# Solicitar al usuario la palabra a reemplazar en telegraf.conf
$organizationName = Read-Host "Introduce el nombre del cliente como está en el proyecto JIRA (Ej: HSCALIU o HGASOC)"

# Generar el archivo organization.conf dentro de la carpeta telegraf.d
$confContent = @"
[global_tags]
  organization = "$organizationName"
"@

Set-Content -Path (Join-Path -Path $telegrafD -ChildPath "organization.conf") -Value $confContent
Write-Host "El archivo organization.conf se ha creado con éxito en la carpeta telegraf.d." -ForegroundColor Green

# Ruta al archivo telegraf.exe
$rutaEjecutable = Join-Path -Path $destino -ChildPath "telegraf.exe"

# Convertir el archivo telegraf.exe en un servicio
cd $destino
.\telegraf.exe --service install --config https://raw.githubusercontent.com/3digitsSistemas/telegraf/main/telegraf.conf --config-directory $destino\telegraf.d
Write-Host "El archivo Telegraf.exe se ha convertido en un servicio." -ForegroundColor Green

# Iniciar el servicio Telegraf
Start-Service -Name "telegraf"

# Esperar unos segundos para que el servicio se inicie completamente
Write-Host "Iniciando servicio Telegraf..." -ForegroundColor Green
Start-Sleep -Seconds 5

# Comprobar si el servicio se ha iniciado correctamente
$serviceStatus = Get-Service -Name $serviceName

if ($serviceStatus.Status -eq "Running") {
    Write-Host "El servicio Telegraf se ha iniciado correctamente." -ForegroundColor Green
} else {
    Write-Host "¡ADVERTENCIA! El servicio Telegraf no se ha iniciado correctamente. Verifica la configuración." -ForegroundColor Red
}

# Configurar el recovery para que el servicio se reinicie en caso de un primer fallo y se configura el inicio automático retrasado
sc.exe failure "telegraf" reset=0 actions=restart/60000/restart/60000/restart/60000
sc.exe config "telegraf" start=delayed-auto
Write-Host "Configurado el recovery para reiniciar el servicio en caso de un primer fallo." -ForegroundColor Green

Write-Host "######################################################################" -ForegroundColor Yellow

Write-Host -NoNewLine 'Pulsa una tecla para continuar...';
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
Exit 0

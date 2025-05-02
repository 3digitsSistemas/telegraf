param (
    [string]$password
)

if (-not $password -and $args.Length -gt 0) {
    $password = $args[0]
}

Write-Host "Script para la instalacion del agente de Telegraf" -ForegroundColor Green
Write-Host "######################################################################" -ForegroundColor Yellow
Write-Host "1.- Comprobando permisos de Administrador"

if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Permisos insuficientes para ejecutar este script. Ejecute el script de PowerShell como administrador."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
    Exit 1
}

Write-Host "- Permisos correctos, iniciando la instalacion del agente de Telegraf" -ForegroundColor Green

# Comprobar si el servicio "telegraf" existe
$serviceName = "telegraf"
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

Write-Host "2.- Comprobando existencia del servicio de telegraf"
if ($service) {
    if ($service.Status -eq "Running") {
        Stop-Service -Name $serviceName -Force
        Start-Sleep -Seconds 5
        Write-Host "- Servicio Telegraf detenido." -ForegroundColor Green
    }
    sc.exe delete $serviceName | Out-Null
    Write-Host "- Servicio Telegraf eliminado." -ForegroundColor Green
}

# Definir directorio
$destino = "C:\Program Files\Telegraf"

Write-Host "3.- Comprobando directorio telegraf"
if (Test-Path -Path $destino -PathType Container) {
    Remove-Item -Path $destino -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    Write-Host "- Directorio $destino eliminado con todo su contenido." -ForegroundColor Green
}

New-Item -Path $destino -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
Write-Host "- Directorio $destino creado." -ForegroundColor Green

$telegrafD = Join-Path -Path $destino -ChildPath "telegraf.d"
New-Item -Path $telegrafD -ItemType Directory > $null
Write-Host "- El directorio telegraf.d se ha creado en $destino." -ForegroundColor Green

Write-Host "4.- Descargando la última versión del agente Telegraf"

# Obtener última versión desde GitHub
$githubApiUrl = "https://api.github.com/repos/influxdata/telegraf/releases/latest"
$headers = @{ "User-Agent" = "PowerShellScript" }

try {
    $releaseInfo = Invoke-RestMethod -Uri $githubApiUrl -Headers $headers
    $latestVersion = $releaseInfo.tag_name.TrimStart("v")
    $asset = $releaseInfo.assets | Where-Object { $_.name -like "*windows_amd64.zip" }

    if (-not $asset) {
        Write-Host "No se encontró versión de Windows en el último release." -ForegroundColor Red
        Exit 1
    }

    $downloadUrl = $asset.browser_download_url
    $zipPath = Join-Path -Path $destino -ChildPath $asset.name
    Write-Host "- Última versión detectada: $latestVersion" -ForegroundColor Green
    Write-Host "- Descargando desde: $downloadUrl" -ForegroundColor Yellow

    Invoke-WebRequest -Uri $downloadUrl -UseBasicParsing -OutFile $zipPath
}
catch {
    Write-Host "Error al consultar la versión más reciente: $_" -ForegroundColor Red
    Exit 1
}

# Descomprimir y preparar archivos
Expand-Archive -Path $zipPath -DestinationPath $destino
$folderDescomprimido = Join-Path -Path $destino -ChildPath ("telegraf-" + $latestVersion)
Move-Item -Path (Join-Path $folderDescomprimido "telegraf.*") -Destination $destino
Remove-Item -Path $zipPath
Remove-Item -Path $folderDescomprimido -Recurse -Force
Remove-Item -Path (Join-Path -Path $destino -ChildPath "telegraf.conf") -Recurse -Force

Write-Host "5.- Determinando nombre de organización"

$domainName = $env:USERDNSDOMAIN
if ($domainName -and $domainName -ne "") {
    $organizationName = $domainName
    Write-Host "- Nombre de dominio detectado: $domainName." -ForegroundColor Green
} else {
    $organizationName = Read-Host "- Equipo fuera de dominio, introduce el nombre del cliente como esta en el proyecto JIRA (Ej: HSCALIU o HGASOC)"
}

$confContent = @"
[global_tags]
  organization = "$organizationName"
"@
Set-Content -Path (Join-Path -Path $telegrafD -ChildPath "organization.conf") -Value $confContent
Write-Host "- El archivo organization.conf se ha creado con éxito." -ForegroundColor Green

Write-Host "6.- Configurando conexión con BBDD"
if (-not $password) {
    $password = Read-Host "- Introduce el password de la BBDD"
}

$outputsContent = @"
[[outputs.influxdb]]
   urls = ["http://metrics.3digits.es:8086"]
   database = "telegraf"
   username = "metrics"
   password = "$password"
"@
Set-Content -Path (Join-Path -Path $telegrafD -ChildPath "outputs.conf") -Value $outputsContent -Encoding UTF8
Write-Host "- El archivo outputs.conf se ha creado con éxito." -ForegroundColor Green

# Crear servicio
$rutaEjecutable = Join-Path -Path $destino -ChildPath "telegraf.exe"
cd $destino
.\telegraf.exe --service install --config https://raw.githubusercontent.com/3digitsSistemas/telegraf/main/telegraf.conf --config-directory $destino\telegraf.d
Write-Host "7.- Convirtiendo telegraf.exe en servicio del sistema..."

Start-Service -Name "telegraf"
Write-Host "- Iniciando servicio Telegraf..." -ForegroundColor Green
Start-Sleep -Seconds 5

$serviceStatus = Get-Service -Name $serviceName
if ($serviceStatus.Status -eq "Running") {
    Write-Host "- El servicio Telegraf se ha iniciado correctamente." -ForegroundColor Green
} else {
    Write-Host "¡ADVERTENCIA! El servicio Telegraf no se ha iniciado correctamente." -ForegroundColor Red
}

# Configuración de recuperación
sc.exe failure "telegraf" reset=0 actions=restart/60000/restart/60000/restart/60000 | Out-Null
sc.exe config "telegraf" start=delayed-auto | Out-Null
Write-Host "8.- Configurado recovery para reinicio automático del servicio." -ForegroundColor Green

Write-Host "######################################################################" -ForegroundColor Yellow
Write-Host -NoNewLine 'Pulsa una tecla para continuar...';
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
Exit 0

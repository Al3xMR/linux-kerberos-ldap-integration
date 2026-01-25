# ==============================================================================
# SETUP CLIENTE WINDOWS: RED + KERBEROS + PUTTY
# Autor: Kevin Martinez
# Requisito: Click derecho -> "Ejecutar con PowerShell" (Como Administrador)
# ==============================================================================

# 0. VERIFICAR PERMISOS DE ADMIN
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Error: Debes ejecutar este script como Administrador." -ForegroundColor Red
    Write-Host "Haz clic derecho en el archivo y selecciona 'Ejecutar con PowerShell'."
    Read-Host "Presiona Enter para salir..."
    exit
}

Clear-Host
Write-Host "=== CONFIGURACION TOTAL DEL CLIENTE FIS EPN ===" -ForegroundColor Cyan

# 1. SOLICITAR IP DEL SERVIDOR
# ============================
$ServerIP = Read-Host "Introduce la IP de tu servidor Linux (srv-fis)"
if ([string]::IsNullOrWhiteSpace($ServerIP)) { Write-Error "IP Invalida"; exit }

# 2. CONFIGURAR TARJETA DE RED (DNS + IPv6)
# =========================================
Write-Host "`n[1/4] Configurando Adaptador de Red..." -ForegroundColor Green

# Detectar el adaptador conectado (con mayor velocidad de enlace)
$Adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Sort-Object -Descending LinkSpeed | Select-Object -First 1

if ($Adapter) {
    Write-Host "-> Adaptador detectado: $($Adapter.Name) ($($Adapter.InterfaceDescription))" -ForegroundColor Yellow
    
    # A. DESACTIVAR IPv6
    Write-Host "   - Desactivando IPv6 para evitar conflictos..."
    Disable-NetAdapterBinding -Name $Adapter.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
    
    # B. CAMBIAR DNS (Primario: Tu Servidor, Secundario: Google)
    Write-Host "   - Estableciendo DNS a $ServerIP..."
    Set-DnsClientServerAddress -InterfaceIndex $Adapter.InterfaceIndex -ServerAddresses ($ServerIP, "8.8.8.8")
    
    # C. LIMPIAR CACHE
    Clear-DnsClientCache
    Write-Host "-> Red configurada correctamente." -ForegroundColor Cyan
} else {
    Write-Host "ERROR: No se detecto ninguna tarjeta de red conectada." -ForegroundColor Red
    exit
}

# 3. CREAR ARCHIVO KRB5.INI
# =========================
Write-Host "`n[2/4] Configurando Kerberos (krb5.ini)..." -ForegroundColor Green
$KrbPath = "C:\ProgramData\MIT\Kerberos5"
if (!(Test-Path -Path $KrbPath)) { New-Item -ItemType Directory -Force -Path $KrbPath | Out-Null }

$KrbContent = @"
[libdefaults]
    default_realm = FIS.EPN.EDU.EC
    dns_lookup_realm = true
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true

[realms]
    FIS.EPN.EDU.EC = {
    }

[domain_realm]
    .fis.epn.edu.ec = FIS.EPN.EDU.EC
    fis.epn.edu.ec = FIS.EPN.EDU.EC
"@
Set-Content -Path "$KrbPath\krb5.ini" -Value $KrbContent -Encoding ASCII

# 4. CONFIGURAR PUTTY (REGISTRO)
# ==============================
Write-Host "`n[3/4] Creando perfil automatico en PuTTY..." -ForegroundColor Green
$RegPath = "HKCU:\Software\SimonTatham\PuTTY\Sessions\FIS-EPN-Automatico"

# Si no existe la ruta, la creamos (Aunque New-ItemProperty suele hacerlo, es mas seguro asi)
if (!(Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }

# Valores clave para SSO
New-ItemProperty -Path $RegPath -Name "HostName" -Value "fis.epn.edu.ec" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $RegPath -Name "GSSAPIAuthentication" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $RegPath -Name "GSSAPIDelegateCredentials" -Value 1 -PropertyType DWord -Force | Out-Null
# ¡IMPORTANTE! Habilitar Canonicalizacion para que resuelva al nombre largo si es necesario
New-ItemProperty -Path $RegPath -Name "GSSAPICanonicalise" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $RegPath -Name "UseSystemColours" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $RegPath -Name "Protocol" -Value "ssh" -PropertyType String -Force | Out-Null

Write-Host "-> Perfil 'FIS-EPN-Automatico' inyectado en el registro." -ForegroundColor Cyan

# 5. VERIFICACIÓN FINAL
# =====================
Write-Host "`n[4/4] Verificando conectividad..." -ForegroundColor Green
Start-Sleep -Seconds 2 # Dar tiempo a que la red se asiente
try {
    $Result = Resolve-DnsName -Name "_kerberos._udp.fis.epn.edu.ec" -Type SRV -ErrorAction Stop
    Write-Host "-> EXITO TOTAL: El DNS respondio y Kerberos es visible." -ForegroundColor Cyan
    Write-Host "   KDC Target: $($Result.NameTarget)"
} catch {
    Write-Host "-> ADVERTENCIA: Windows aun no detecta el dominio. Puede requerir reiniciar o desconectar/conectar Wi-Fi." -ForegroundColor Yellow
}

Write-Host "`n=== PROCESO TERMINADO ===" -ForegroundColor Cyan
Write-Host "1. Abre MIT Kerberos -> Get Ticket"
Write-Host "2. Abre PuTTY -> Carga 'FIS-EPN-Automatico'"
Read-Host "Presiona Enter para salir..."
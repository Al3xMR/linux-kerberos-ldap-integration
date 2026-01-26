#!/bin/bash

# ==============================================================================
# SCRIPT DE CLIENTE: UNIRSE AL DOMINIO FIS.EPN.EDU.EC
# Autor: Kevin Martinez
# Descripción: Configura DNS, instala Kerberos y prepara SSH automáticamente.
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
    echo "Por favor, ejecuta como root (sudo ./unir_cliente.sh)"
    exit 1
fi

# Colores
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}=== CONFIGURACIÓN DE CLIENTE KERBEROS ===${NC}"

# 1. SOLICITAR IP DEL SERVIDOR
# ============================
echo -e "Introduce la IP de tu servidor (srv-fis):"
read -p "> " IP_SRV

if [[ ! $IP_SRV =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Formato de IP inválido."
    exit 1
fi

# 2. CONFIGURAR DNS (RESOLV.CONF)
# ============================
echo -e "${CYAN}[1/4] Apuntando DNS al servidor...${NC}"
# Hacemos backup por si acaso
cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null

# Forzamos el DNS local primero, y Google de respaldo
cat <<EOF > /etc/resolv.conf
nameserver $IP_SRV
nameserver 8.8.8.8
search fis.epn.edu.ec
EOF

# Prueba rápida de conexión
echo "Verificando conexión con el dominio..."
if ping -c 1 fis.epn.edu.ec > /dev/null 2>&1; then
    echo -e "${GREEN}-> DNS Responde correctamente.${NC}"
else
    echo -e "${GREEN}[ADVERTENCIA] El dominio no responde al Ping. Verifica la IP.${NC}"
    # No salimos, por si es solo bloqueo de ICMP
fi

# 3. INSTALAR PAQUETES (SILENCIOSO)
# ============================
echo -e "${CYAN}[2/4] Instalando Cliente Kerberos...${NC}"
export DEBIAN_FRONTEND=noninteractive

# Pre-configuramos para que NO pida el Reino en pantalla azul
echo "krb5-config krb5-config/default_realm string FIS.EPN.EDU.EC" | debconf-set-selections
echo "krb5-config krb5-config/add_servers_realm boolean true" | debconf-set-selections

apt-get update -qq
apt-get install -y krb5-user -qq

# 4. CONFIGURAR KERBEROS (MODO DNS)
# ============================
echo -e "${CYAN}[3/4] Configurando krb5.conf inteligente...${NC}"
cat <<EOF > /etc/krb5.conf
[libdefaults]
    default_realm = FIS.EPN.EDU.EC
    dns_lookup_realm = true
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true

[realms]
    # Se deja vacío para usar descubrimiento DNS SRV
    FIS.EPN.EDU.EC = {
    }

[domain_realm]
    .fis.epn.edu.ec = FIS.EPN.EDU.EC
    fis.epn.edu.ec = FIS.EPN.EDU.EC
EOF

# 5. ACTIVAR SSH AUTOMÁTICO (CLIENTE)
# ============================
echo -e "${CYAN}[4/4] Configurando Cliente SSH...${NC}"
# Esto evita tener que escribir "-K" o "-o GSSAPI..." cada vez
# Modificamos /etc/ssh/ssh_config (Configuración global del cliente)

if ! grep -q "GSSAPIAuthentication yes" /etc/ssh/ssh_config; then
    echo "    GSSAPIAuthentication yes" >> /etc/ssh/ssh_config
    echo "    GSSAPIDelegateCredentials yes" >> /etc/ssh/ssh_config
fi

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}       CLIENTE CONFIGURADO CON ÉXITO      ${NC}"
echo -e "${GREEN}==========================================${NC}"
echo "Prueba ahora: 'kinit usuario' y luego 'ssh usuario@fis.epn.edu.ec'"
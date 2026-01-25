#!/bin/bash

# ==============================================================================
# PROYECTO 2: SERVICIO DE DIRECTORIO Y AUTENTICACIÓN INTEGRADO (FIS-EPN)
# Autor: Kevin Martinez
# Versión: 3.1 (Verificación Root + Arquitectura Install-First)
# ==============================================================================

# 0. VERIFICACIÓN DE SEGURIDAD (ROOT CHECK)
# =========================================
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[0;31m[ERROR] Acceso denegado.\033[0m"
    echo "Este script requiere privilegios de superusuario para instalar paquetes."
    echo "Uso correcto: sudo $0"
    exit 1
fi

# 1. VARIABLES GLOBALES
# =====================
DOMAIN="fis.epn.edu.ec"
REALM="FIS.EPN.EDU.EC"
SRV_NAME="srv-fis"
IP_SRV=$(hostname -I | awk '{print $1}') 
PASS_ADMIN="Sistemas2026."

# Colores para logs
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}==================================================${NC}"
echo -e "${GREEN} INICIANDO DESPLIEGUE - PROYECTO 2 (v3.1)${NC}"
echo " IP Detectada: $IP_SRV"
echo -e "${GREEN}==================================================${NC}"

# ====================================================
# FASE 0: PREPARACIÓN E INSTALACIÓN (CON INTERNET)
# ====================================================
echo -e "${GREEN}[FASE 0] Instalando Paquetes (Usando DNS externo)...${NC}"

# 0.1 Asegurar salida a internet (DNS de Google temporal)
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# 0.2 Pre-configuración para instalación silenciosa
export DEBIAN_FRONTEND=noninteractive
# Kerberos
echo "krb5-config krb5-config/default_realm string $REALM" | debconf-set-selections
echo "krb5-config krb5-config/add_servers_realm boolean true" | debconf-set-selections
# LDAP
echo "slapd slapd/domain string $DOMAIN" | debconf-set-selections
echo "slapd slapd/root_password password $PASS_ADMIN" | debconf-set-selections
echo "slapd slapd/root_password_again password $PASS_ADMIN" | debconf-set-selections

# 0.3 INSTALACIÓN MASIVA
apt-get update
apt-get install -y bind9 bind9utils chrony krb5-kdc krb5-admin-server slapd ldap-utils

# ====================================================
# FASE 1: INFRAESTRUCTURA DE RED (DNS LOCAL)
# ====================================================
echo -e "${GREEN}[FASE 1] Configurando DNS Local...${NC}"

# 1.1 Configurar Hostname y Hosts
hostnamectl set-hostname $SRV_NAME
echo "127.0.0.1 localhost" > /etc/hosts
echo "$IP_SRV $SRV_NAME.$DOMAIN $SRV_NAME" >> /etc/hosts

# 1.2 Configurar Bind9
# (Nota: Asumimos que la carpeta conf/ existe y tiene los archivos)
if [ -f conf/named.conf.local ]; then
    cp conf/named.conf.local /etc/bind/named.conf.local
    sed "s/IP_SERVIDOR/$IP_SRV/g" conf/db.template > /etc/bind/db.fis.epn.edu.ec
else
    echo -e "${RED}[ERROR] No se encuentra la carpeta conf/ o los archivos de DNS.${NC}"
    exit 1
fi

# 1.3 Activar DNS Local
systemctl restart bind9
# Forzamos al servidor a usarse a sí mismo
echo "nameserver 127.0.0.1" > /etc/resolv.conf
echo " -> Ahora el servidor usa su propio DNS."

# ====================================================
# FASE 2: TIEMPO (CHRONY)
# ====================================================
echo -e "${GREEN}[FASE 2] Configurando Reloj...${NC}"

echo "makestep 1.0 3" >> /etc/chrony/chrony.conf
systemctl restart chrony
chronyc makestep || echo " -> Advertencia: Chrony no pudo hacer salto (¿ya sincronizado?)"
echo " -> Reloj configurado."

# ====================================================
# FASE 3: KERBEROS (AUTENTICACIÓN)
# ====================================================
echo -e "${GREEN}[FASE 3] Configurando Kerberos...${NC}"

# 3.1 Configuración (krb5.conf)
cat <<EOF > /etc/krb5.conf
[libdefaults]
    default_realm = $REALM
    dns_lookup_kdc = true
    dns_lookup_realm = false
    clockskew = 300

[realms]
    $REALM = {
        kdc = $SRV_NAME.$DOMAIN
        admin_server = $SRV_NAME.$DOMAIN
    }

[domain_realm]
    .$DOMAIN = $REALM
    $DOMAIN = $REALM
EOF

# 3.2 Crear Base de Datos
if [ -f /var/lib/krb5kdc/principal ]; then
    kdb5_util destroy -f
fi
kdb5_util create -s -P "$PASS_ADMIN"

# 3.3 Crear Admin
kadmin.local -q "addprinc -pw $PASS_ADMIN admin/admin"

systemctl restart krb5-kdc
systemctl restart krb5-admin-server

# ====================================================
# FASE 4: LDAP (DIRECTORIO)
# ====================================================
echo -e "${GREEN}[FASE 4] Configurando OpenLDAP...${NC}"

# 4.1 Cargar Esquemas Básicos
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/ldap/schema/cosine.ldif > /dev/null 2>&1
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/ldap/schema/nis.ldif > /dev/null 2>&1
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/ldap/schema/inetorgperson.ldif > /dev/null 2>&1

# 4.2 REPARAR CONTRASEÑA ADMIN (Fix Crítico)
cat <<EOF > /tmp/repair_db.ldif
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=admin,dc=fis,dc=epn,dc=edu,dc=ec
-
replace: olcRootPW
olcRootPW: $PASS_ADMIN
EOF
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/repair_db.ldif

# 4.3 Generar y Cargar Estructura (People/Groups)
cat <<EOF > /tmp/base_structure.ldif
dn: dc=fis,dc=epn,dc=edu,dc=ec
objectClass: top
objectClass: dcObject
objectClass: organization
o: FIS EPN
dc: fis

dn: ou=People,dc=fis,dc=epn,dc=edu,dc=ec
objectClass: organizationalUnit
ou: People

dn: ou=Groups,dc=fis,dc=epn,dc=edu,dc=ec
objectClass: organizationalUnit
ou: Groups

dn: cn=estudiantes,ou=Groups,dc=fis,dc=epn,dc=edu,dc=ec
objectClass: posixGroup
cn: estudiantes
gidNumber: 2000

dn: cn=profesores,ou=Groups,dc=fis,dc=epn,dc=edu,dc=ec
objectClass: posixGroup
cn: profesores
gidNumber: 5000
EOF

# Cargamos estructura (-c para continuar si hay errores de duplicados)
ldapadd -c -x -D "cn=admin,dc=fis,dc=epn,dc=edu,dc=ec" -w "$PASS_ADMIN" -f /tmp/base_structure.ldif

echo -e "${GREEN}==================================================${NC}"
echo -e "${GREEN} DESPLIEGUE FINALIZADO EXITOSAMENTE${NC}"
echo -e "${GREEN}==================================================${NC}"

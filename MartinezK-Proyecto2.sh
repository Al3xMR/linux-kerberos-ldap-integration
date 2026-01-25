#!/bin/bash

# ==============================================================================
# PROYECTO 2: SISTEMA INTEGRADO DE IDENTIDAD (FIS-EPN)
# Autor: Kevin Martinez
# Versión: 6.1 (Fix: Prevención de errores BIND duplicados)
# ==============================================================================

if [ "$EUID" -ne 0 ]; then echo "Ejecutar como root (sudo)."; exit 1; fi

# 1. VARIABLES GLOBALES
DOMAIN="fis.epn.edu.ec"
REALM="FIS.EPN.EDU.EC"
SRV_NAME="srv-fis"
IP_SRV=$(hostname -I | awk '{print $1}')
PASS_ADMIN="Sistemas2026."
USER_DEMO="kevin.martinez"
PASS_DEMO="Kevin123."

# Colores
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}=== INICIANDO DESPLIEGUE v6.1 ===${NC}"
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# ====================================================
# FASE 0: INSTALACIÓN DE PAQUETES
# ====================================================
echo -e "${CYAN}[FASE 0] Instalando Software...${NC}"
export DEBIAN_FRONTEND=noninteractive

# Pre-configuración
echo "krb5-config krb5-config/default_realm string $REALM" | debconf-set-selections
echo "krb5-config krb5-config/add_servers_realm boolean true" | debconf-set-selections
echo "slapd slapd/domain string $DOMAIN" | debconf-set-selections
echo "slapd slapd/root_password password $PASS_ADMIN" | debconf-set-selections
echo "slapd slapd/root_password_again password $PASS_ADMIN" | debconf-set-selections
echo "libnss-ldapd nslcd/ldap-uris string ldap://127.0.0.1/" | debconf-set-selections
echo "libnss-ldapd nslcd/ldap-base string dc=fis,dc=epn,dc=edu,dc=ec" | debconf-set-selections

apt-get update
apt-get install -y bind9 bind9utils chrony krb5-kdc krb5-admin-server slapd ldap-utils openssh-server libnss-ldapd libpam-ldapd nscd

# ====================================================
# FASE 1: DNS (BIND9) - CORREGIDO
# ====================================================
echo -e "${CYAN}[FASE 1] Configurando DNS...${NC}"
hostnamectl set-hostname $SRV_NAME
echo "127.0.0.1 localhost" > /etc/hosts
echo "$IP_SRV $SRV_NAME.$DOMAIN $SRV_NAME" >> /etc/hosts

if [ -f conf/named.conf.local ]; then
    cp conf/named.conf.local /etc/bind/named.conf.local
    sed "s/IP_SERVIDOR/$IP_SRV/g" conf/db.template > /etc/bind/db.fis.epn.edu.ec

    # --- CORRECCIÓN AQUÍ: Sobrescribimos el archivo en lugar de editarlo con sed ---
    cat <<EOF > /etc/bind/named.conf.options
options {
    directory "/var/cache/bind";
    allow-query { any; };
    listen-on { any; };
    dnssec-validation no;
    listen-on-v6 { any; };
};
EOF
    # -------------------------------------------------------------------------------

    systemctl restart bind9
    echo "nameserver 127.0.0.1" > /etc/resolv.conf
else
    echo "[ERROR] Faltan archivos en la carpeta conf/"; exit 1
fi

# ====================================================
# FASE 2: NTP (CHRONY)
# ====================================================
echo -e "${CYAN}[FASE 2] Sincronizando Tiempo...${NC}"
# Limpiamos config vieja antes de agregar
grep -q "makestep" /etc/chrony/chrony.conf || echo "makestep 1.0 3" >> /etc/chrony/chrony.conf
systemctl restart chrony
chronyc makestep || true

# ====================================================
# FASE 3: KERBEROS SERVER (KDC)
# ====================================================
echo -e "${CYAN}[FASE 3] Configurando KDC...${NC}"
cat <<EOF > /etc/krb5.conf
[libdefaults]
    default_realm = $REALM
    dns_lookup_kdc = true
    dns_lookup_realm = false
[realms]
    $REALM = {
        kdc = $SRV_NAME.$DOMAIN
        admin_server = $SRV_NAME.$DOMAIN
    }
[domain_realm]
    .$DOMAIN = $REALM
    $DOMAIN = $REALM
EOF

if [ -f /var/lib/krb5kdc/principal ]; then kdb5_util destroy -f; fi
kdb5_util create -s -P "$PASS_ADMIN"
kadmin.local -q "addprinc -pw $PASS_ADMIN admin/admin"
systemctl restart krb5-kdc krb5-admin-server

# ====================================================
# FASE 4: LDAP SERVER
# ====================================================
echo -e "${CYAN}[FASE 4] Configurando LDAP Server...${NC}"
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/ldap/schema/cosine.ldif >/dev/null 2>&1
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/ldap/schema/nis.ldif >/dev/null 2>&1
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/ldap/schema/inetorgperson.ldif >/dev/null 2>&1

# Fix Password Admin
cat <<EOF > /tmp/repair.ldif
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=admin,dc=fis,dc=epn,dc=edu,dc=ec
-
replace: olcRootPW
olcRootPW: $PASS_ADMIN
EOF
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/repair.ldif

# Estructura Base
cat <<EOF > /tmp/base.ldif
dn: dc=fis,dc=epn,dc=edu,dc=ec
objectClass: top
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
EOF
ldapadd -c -x -D "cn=admin,dc=fis,dc=epn,dc=edu,dc=ec" -w "$PASS_ADMIN" -f /tmp/base.ldif

# ====================================================
# FASE 4.5: INTEGRACIÓN CLIENTE (NSSWITCH)
# ====================================================
echo -e "${CYAN}[FASE 4.5] Configurando Cliente LDAP (getent)...${NC}"

# Configuración limpia de nslcd.conf (Sobrescritura segura)
cat <<EOF > /etc/nslcd.conf
uid nslcd
gid nslcd
uri ldap://127.0.0.1/
base dc=fis,dc=epn,dc=edu,dc=ec
binddn cn=admin,dc=fis,dc=epn,dc=edu,dc=ec
bindpw $PASS_ADMIN
ssl no
tls_reqcert never
EOF
chmod 600 /etc/nslcd.conf

# Reset y configuración de nsswitch.conf
sed -i 's/^passwd:.*/passwd:         files systemd ldap/' /etc/nsswitch.conf
sed -i 's/^group:.*/group:          files systemd ldap/' /etc/nsswitch.conf
sed -i 's/^shadow:.*/shadow:         files ldap/' /etc/nsswitch.conf

systemctl restart nslcd
systemctl restart nscd

# ====================================================
# FASE 5: SSH CON KERBEROS (SSO)
# ====================================================
echo -e "${CYAN}[FASE 5] Configurando SSH...${NC}"

# Limpieza previa de Keytab
rm -f /etc/krb5.keytab
kadmin.local -q "addprinc -randkey host/$SRV_NAME.$DOMAIN"
kadmin.local -q "ktadd host/$SRV_NAME.$DOMAIN"

# Configuración SSH segura
sed -i 's/^#GSSAPIAuthentication.*/GSSAPIAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^GSSAPIAuthentication.*/GSSAPIAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#GSSAPICleanupCredentials.*/GSSAPICleanupCredentials yes/' /etc/ssh/sshd_config
sed -i 's/^UsePAM no/UsePAM yes/' /etc/ssh/sshd_config

systemctl restart ssh

# ====================================================
# FASE 6: USUARIO DEMO
# ====================================================
echo -e "${CYAN}[FASE 6] Creando usuario Demo: $USER_DEMO...${NC}"

cat <<EOF > /tmp/demo.ldif
dn: uid=$USER_DEMO,ou=People,dc=fis,dc=epn,dc=edu,dc=ec
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Kevin Martinez
sn: Martinez
uid: $USER_DEMO
uidNumber: 1001
gidNumber: 2000
homeDirectory: /home/$USER_DEMO
loginShell: /bin/bash
gecos: Kevin Martinez
userPassword: {crypt}x
shadowLastChange: 19748
shadowMax: 99999
shadowWarning: 7
EOF
ldapadd -x -D "cn=admin,dc=fis,dc=epn,dc=edu,dc=ec" -w "$PASS_ADMIN" -f /tmp/demo.ldif >/dev/null 2>&1

if ! kadmin.local -q "getprinc $USER_DEMO" | grep -q "Principal: $USER_DEMO"; then
    kadmin.local -q "addprinc -pw $PASS_DEMO $USER_DEMO"
fi

if [ ! -d "/home/$USER_DEMO" ]; then
    mkdir -p /home/$USER_DEMO
    cp -r /etc/skel/. /home/$USER_DEMO
    chown -R 1001:2000 /home/$USER_DEMO
fi

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}       DESPLIEGUE FINALIZADO v6.1       ${NC}"
echo -e "${GREEN}==========================================${NC}"
echo "Test Rápido: getent passwd $USER_DEMO"

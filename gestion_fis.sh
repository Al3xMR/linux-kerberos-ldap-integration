#!/bin/bash

# ==============================================================================
# SCRIPT DE GESTIÓN DE USUARIOS (CRUD v2) - FIS EPN
# ==============================================================================

# CONFIGURACIÓN
DOMAIN_DN="dc=fis,dc=epn,dc=edu,dc=ec"
ADMIN_DN="cn=admin,$DOMAIN_DN"
PASS_ADMIN="Sistemas2026." 
REALM="FIS.EPN.EDU.EC"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Verificación Root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Ejecutar como root (sudo).${NC}"
    exit 1
fi

# ==============================================================================
# FUNCIONES
# ==============================================================================

crear_usuario() {
    echo -e "\n${BLUE}=== CREAR NUEVO USUARIO ===${NC}"
    read -p "Nombre de usuario (ej: juan.perez): " USER_ID
    read -p "Nombre (ej: Juan): " NOMBRE
    read -p "Apellido (ej: Perez): " APELLIDO
    
    echo "Seleccione el Rol:"
    echo "  1) Estudiante (GID 2000)"
    echo "  2) Profesor (GID 5000)"
    echo "  3) Administrativo (GID 3000)" # <--- NUEVO
    read -p "Opción: " ROL_OPT

    case $ROL_OPT in
        1) GID=2000; DESC="Estudiante" ;;
        2) GID=5000; DESC="Profesor" ;;
        3) GID=3000; DESC="Administrativo" ;; # <--- NUEVO
        *) echo -e "${RED}Opción inválida.${NC}"; return ;;
    esac

    UID_NUM=$((3000 + RANDOM % 5000))

    echo -e "${GREEN}Creando a $NOMBRE $APELLIDO ($USER_ID) - $DESC...${NC}"

    # Crear LDIF
    cat <<EOF > /tmp/new_user.ldif
dn: uid=$USER_ID,ou=People,$DOMAIN_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: $NOMBRE $APELLIDO
sn: $APELLIDO
uid: $USER_ID
uidNumber: $UID_NUM
gidNumber: $GID
homeDirectory: /home/$USER_ID
loginShell: /bin/bash
gecos: $NOMBRE $APELLIDO
userPassword: {crypt}x
shadowLastChange: 0
shadowMax: 99999
shadowWarning: 7
EOF

    # Insertar en LDAP
    ldapadd -x -D "$ADMIN_DN" -w "$PASS_ADMIN" -f /tmp/new_user.ldif > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "[LDAP] Usuario agregado correctamente."
    else
        echo -e "${RED}[LDAP] Error: El usuario ya existe o falló la conexión.${NC}"
        rm /tmp/new_user.ldif
        return
    fi
    rm /tmp/new_user.ldif

    # Insertar en Kerberos
    echo -e "[KERBEROS] Asignando contraseña..."
    kadmin.local -q "addprinc $USER_ID"

    # Crear Home (Necesario para 'su - usuario')
    if [ ! -d "/home/$USER_ID" ]; then
        mkdir -p /home/$USER_ID
        cp -r /etc/skel/. /home/$USER_ID
        chown -R $UID_NUM:$GID /home/$USER_ID
        echo -e "[SISTEMA] Carpeta personal creada."
    fi

    echo -e "${GREEN}¡Listo!${NC}"
    read -p "Enter para continuar..."
}

listar_usuarios() {
    echo -e "\n${BLUE}=== LISTADO DE PERSONAL (LDAP) ===${NC}"
    
    # Comprobamos si hay alguien primero
    COUNT=$(ldapsearch -x -b "ou=People,$DOMAIN_DN" "(objectClass=posixAccount)" uid | grep -c "uid:")
    
    if [ "$COUNT" -eq "0" ]; then
        echo -e "${RED}No se encontraron usuarios en la base de datos.${NC}"
    else
        echo -e "Se encontraron $COUNT usuarios:\n"
        # Listado simplificado y robusto (Muestra DN, UID y CN)
        ldapsearch -x -b "ou=People,$DOMAIN_DN" "(objectClass=posixAccount)" uid uidNumber gidNumber cn | grep -E "uid:|uidNumber:|gidNumber:|cn:"
    fi
    echo "---------------------------------------------------------------"
    read -p "Enter para continuar..."
}

modificar_usuario() {
    echo -e "\n${BLUE}=== MODIFICAR USUARIO ===${NC}"
    read -p "Usuario a modificar (uid): " USER_ID

    # Verificación simple
    if ! ldapsearch -x -b "ou=People,$DOMAIN_DN" "(uid=$USER_ID)" uid | grep -q "uid: $USER_ID"; then
        echo -e "${RED}El usuario no existe.${NC}"
        read -p "Enter..."
        return
    fi

    echo "1) Cambiar Contraseña (Kerberos)"
    echo "2) Cambiar Shell (LDAP)"
    read -p "Opción: " MOD_OPT

    if [ "$MOD_OPT" == "1" ]; then
        kadmin.local -q "cpw $USER_ID"
    elif [ "$MOD_OPT" == "2" ]; then
        read -p "Nueva Shell (ej: /bin/sh): " NEW_SHELL
        echo -e "dn: uid=$USER_ID,ou=People,$DOMAIN_DN\nchangetype: modify\nreplace: loginShell\nloginShell: $NEW_SHELL" | \
        ldapmodify -x -D "$ADMIN_DN" -w "$PASS_ADMIN"
        echo "Shell actualizada."
    fi
    read -p "Enter..."
}

eliminar_usuario() {
    echo -e "\n${BLUE}=== ELIMINAR USUARIO ===${NC}"
    read -p "Usuario a eliminar (uid): " USER_ID

    echo -e "${RED}¿Seguro que desea eliminar a $USER_ID? (s/n)${NC}"
    read CONFIRM
    if [ "$CONFIRM" != "s" ]; then return; fi

    # Borrar LDAP
    ldapdelete -x -D "$ADMIN_DN" -w "$PASS_ADMIN" "uid=$USER_ID,ou=People,$DOMAIN_DN"
    
    # Borrar Kerberos
    kadmin.local -q "delprinc -force $USER_ID" > /dev/null 2>&1
    
    echo -e "${GREEN}Usuario eliminado.${NC}"
    read -p "Enter..."
}

# ==============================================================================
# MENU
# ==============================================================================
while true; do
    clear
    echo -e "${GREEN}   GESTIÓN FIS (CRUD v2)${NC}"
    echo "1. Listar Usuarios"
    echo "2. Crear Usuario"
    echo "3. Modificar Usuario"
    echo "4. Eliminar Usuario"
    echo "5. Salir"
    read -p "Opción: " OPCION

    case $OPCION in
        1) listar_usuarios ;;
        2) crear_usuario ;;
        3) modificar_usuario ;;
        4) eliminar_usuario ;;
        5) exit 0 ;;
        *) echo "Error." ;;
    esac
done

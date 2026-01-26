# Guía de Configuración: Cliente Windows (Kerberos + SSH)

Esta guía detalla los pasos para configurar una estación de trabajo Windows 10/11 para autenticarse contra el servidor Kerberos `FIS.EPN.EDU.EC` y acceder vía SSH sin contraseña (Single Sign-On).

## Requisitos Previos

Antes de configurar la red o los scripts, es **obligatorio** instalar el siguiente software:

1.  **MIT Kerberos for Windows (64-bit)**
    * Descarga oficial: [MIT Kerberos Dist](https://web.mit.edu/kerberos/dist/index.html)
    * *Nota:* Reinicia el equipo después de instalar para asegurar que las variables de entorno se carguen.
2.  **PuTTY (SSH Client)**
    * Descarga: [PuTTY.org](https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html)

---

## Opción A: Configuración Automática (Recomendada)

Se preparó un script de PowerShell que realiza todas las configuraciones de red, seguridad y registro automáticamente.

**Ubicación del script:** `../client_config_scripts/windows_client.ps1`

### Pasos:

1.  Abre la carpeta donde descargaste el repositorio.
2.  Haz clic derecho en una zona vacía de la carpeta y abre PowerShell **como Administrador**.
3.  Ejecuta el siguiente comando para permitir la ejecución del script (Bypass de seguridad temporal):

```powershell
powershell -ExecutionPolicy Bypass -File ..\client_config_scripts\windows_client.ps1
```

4. Sigue las instrucciones en pantalla:
* Ingresa la **IP del Servidor Linux** cuando se te solicite.
* El script configurará el DNS, desactivará IPv6 y creará el perfil de PuTTY.

![Ejecución del script de configuración automática en PowerShell](./img/2_Windows_ScriptExec.png)

---

## Opción B: Configuración Manual

Si prefieres configurar el cliente paso a paso, sigue estas instrucciones.

### 1. Configuración de Red (DNS)

Kerberos requiere que el cliente pueda resolver los registros SRV del dominio.

* Ve a **Panel de Control > Centro de Redes y Recursos > Cambiar configuración del adaptador**.
* Haz clic derecho en tu adaptador (Wi-Fi o Ethernet) > **Propiedades**.
* **Desmarca** la casilla "Protocolo de Internet versión 6 (TCP/IPv6)".
* En "Protocolo de Internet versión 4 (TCP/IPv4)", configura el **DNS Preferido** con la IP de tu servidor Linux (ej: `192.168.1.x`).

![Configuración manual de red y DNS en el Panel de Control](./img/1_Windows_AdapterSettings.png)

### 2. Archivo de Configuración Kerberos (krb5.ini)

Debes crear el archivo de configuración para que Windows sepa dónde buscar el KDC.

* Ruta del archivo: `C:\ProgramData\MIT\Kerberos5\krb5.ini`
* *Nota:* La carpeta `ProgramData` suele estar oculta.
* Contenido del archivo:

```ini
[libdefaults]
    default_realm = FIS.EPN.EDU.EC
    dns_lookup_realm = true
    dns_lookup_kdc = true
    forwardable = true

[realms]
    FIS.EPN.EDU.EC = {}

[domain_realm]
    .fis.epn.edu.ec = FIS.EPN.EDU.EC
    fis.epn.edu.ec = FIS.EPN.EDU.EC

```

### 3. Configuración de PuTTY

Para lograr el SSO, PuTTY debe configurarse para usar GSSAPI.

1. Abre PuTTY.
2. Ve a **Connection > SSH > Auth > GSSAPI**.
3. Marca las casillas:
* [x] Attempt GSSAPI authentication
* [x] Allow GSSAPI credential delegation

4. Ve a **Session**, pon el Hostname `fis.epn.edu.ec` y guarda la sesión.

---

## Verificación y Uso

>**Nota:** Para realizar estas pruebas, debe usar una cuenta de usuario válida. 

> Puede usar el usuario predeterminado **`kevin.martinez`** con la contraseña **`Kevin123.`** (creada durante la configuración del servidor) o crear una nueva ejecutando el script `gestion_fis.sh` en el servidor.

1. Abre **MIT Kerberos Ticket Manager**.
2. Haz clic en **Get Ticket**.
3. Ingresa tu usuario (ej: `kevin.martinez`) y contraseña.
4. Deberías ver un ticket válido activo.
5. Abre **PuTTY**, carga la sesión guardada y conecta. Deberías ingresar sin contraseña.

![Single-Sign On con SSH en cliente Windows](./img/4_Windows_SSH_Succesful.png)

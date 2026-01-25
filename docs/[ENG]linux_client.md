# Configuration Guide: Linux Client (Ubuntu/Debian)

This guide explains how to configure a secondary Linux machine to act as a client of the `FIS.EPN.EDU.EC` domain, allowing centralized authentication and SSO.

## Prerequisites

* **Root** or `sudo` access on the client machine.
* Network connectivity with the main server (Ping must work).

---

## Option A: Automatic Configuration (Script)

The repository includes a Bash script that automatically installs packages, configures DNS, and adjusts Kerberos settings.

**Script Location:** `../client_config_scripts/ubuntu_client.sh`

### Steps:

1.  Navigate to the scripts folder on the client:
    ```bash
    cd linux-kerberos-ldap-integration/client_config_scripts
    ```

2.  Grant execution permissions to the script:
    ```bash
    chmod +x ubuntu_client.sh
    ```

3.  Run the script as superuser:
    ```bash
    sudo ./ubuntu_client.sh
    ```

4.  Enter the **KDC Server IP** when prompted by the script.

![Running the automatic configuration script in the terminal](./img/3_Linux_ScriptExec.png)

---

## Option B: Manual Configuration

### 1. DNS Configuration
The client must use the KDC server as its nameserver to find the SRV records.

* Edit `/etc/resolv.conf`:
    ```bash
    nameserver [SERVER_IP]
    nameserver 8.8.8.8
    search fis.epn.edu.ec
    ```

### 2. Package Installation
Install the Kerberos user utilities:

```bash
sudo apt update
sudo apt install krb5-user

```

* If prompted for the "Default Realm", type: `FIS.EPN.EDU.EC` (in uppercase).

### 3. Kerberos Configuration

Edit the `/etc/krb5.conf` file to enable DNS lookup:

```ini
[libdefaults]
    default_realm = FIS.EPN.EDU.EC
    dns_lookup_realm = true
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    forwardable = true

[realms]
    FIS.EPN.EDU.EC = {}

[domain_realm]
    .fis.epn.edu.ec = FIS.EPN.EDU.EC
    fis.epn.edu.ec = FIS.EPN.EDU.EC

```

### 4. SSH Configuration (Client)

To avoid typing additional flags when connecting, configure the SSH client globally in `/etc/ssh/ssh_config`:

```bash
# Add to the end of the file
GSSAPIAuthentication yes
GSSAPIDelegateCredentials yes

```

---

## Verification and Usage

> **Note:** To perform these tests, you must use a valid user account. 

> You can use the default user **`kevin.martinez`** with the password **`Kevin123.`** (created during server setup), or create a new one by running the `gestion_fis.sh` script on the server.

1. Obtain a ticket (Login):
```bash
kinit test.user
```

2. Verify the ticket:
```bash
klist
```

*(Must show `krbtgt/FIS.EPN.EDU.EC`)*

3. Connect via SSH to the server:
```bash
ssh test.user@fis.epn.edu.ec
```

*Access should be immediate and without a password.*

![Single-Sign On with SSH on Linux client](./img/5_Linux_SSH_Succesful.png)
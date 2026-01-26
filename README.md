# 🐧 Linux Centralized Authentication System (Kerberos + LDAP + DNS + NTP)

> **Automated deployment of a secure network infrastructure using MIT Kerberos, OpenLDAP, Bind9, and Chrony on Ubuntu Server.**

This project consists of a main Bash script to deploy a **centralized authentication server on Ubuntu**. It creates a Single Sign-On (SSO) ecosystem where users can authenticate via SSH without passwords using Kerberos tickets, while their account information is stored in LDAP.

Additionally, the repository includes **client-side scripts (Bash and PowerShell)** to easily integrate Windows and Linux workstations into this domain.

## 🚀 Features

* **DNS Server (Bind9):** Automatic configuration of Forward/Reverse zones and **SRV Records** for service discovery.
* **Time Synchronization (NTP):** Configures **Chrony** to ensure the server and clients are perfectly synced, a critical requirement for Kerberos security protocols.
* **Kerberos KDC:** Complete setup of the `FIS.EPN.EDU.EC` realm with secure encryption types.
* **OpenLDAP Integration:** Centralized directory for storing user identification data.
* **SSH GSSAPI Support:** Pre-configured SSH daemon to accept Kerberos tickets (passwordless login).
* **Multi-Identity Support:** Servers respond to both FQDN (`srv-fis.fis.epn.edu.ec`) and CNAME/Alias (`fis.epn.edu.ec`).

---

## 📂 Project Structure

```text
linux-kerberos-ldap-integration/
├── MartinezK-Proyecto2.sh      # MAIN SERVER SCRIPT (Ubuntu Server Only)
├── gestion_fis.sh              # TOOL: Manage users in Kerberos & LDAP (Run on Server)
├── client_config_scripts/      # SCRIPTS FOR CLIENTS ONLY
│   ├── windows_client.ps1      # PowerShell automation for Windows Clients
│   └── ubuntu_client.sh        # Bash automation for Linux Clients
├── conf/                       # Configuration templates
│   ├── named.conf.local
│   ├── krb5.conf
│   └── db.template             # DNS Zone template with SRV records
├── data/
│   └── base.ldif               # LDAP base structure
└── docs/                       # CLIENT Documentation (English & Spanish)
    ├── [ENG]windows_client.md  # Windows Client Guide (English)
    ├── [ENG]linux_client.md    # Linux Client Guide (English)
    ├── [SPA]windows_client.md  # Guía Cliente Windows (Español)
    └── [SPA]linux_client.md    # Guía Cliente Linux (Español)
```

---

## 🛠️ Server Installation

### Prerequisites

* **Host OS:** Ubuntu Server 24.04 LTS.
* **Privileges:** Root access (`sudo`).
* **Network:** A static IP is recommended (though the script detects the current IP).

### Installation Steps

1. **Clone the repository:**
```bash
git clone https://github.com/your-username/linux-kerberos-ldap-integration.git
cd linux-kerberos-ldap-integration
```


2. **Make the script executable:**
```bash
chmod +x MartinezK-Proyecto2.sh
```


3. **Run the Main Script:**
```bash
sudo ./MartinezK-Proyecto2.sh
```


4. **Follow the prompts:** The script will update the system, install packages (Bind9, Krb5, Slapd, Chrony), and configure the `FIS.EPN.EDU.EC` domain.

> **Default Registered User:**
> The script automatically creates a default user to test connectivity immediately.
> * **User:** `kevin.martinez`
> * **Password:** `Kevin123.`
> 
> 

---

## 👥 User Management

To manage identities within the domain, use the helper script `gestion_fis.sh`. This tool abstracts the complexity of `kadmin` and `ldapadd` commands.

> **Note:** This script must be run **on the Server**.

```bash
sudo chmod +x gestion_fis.sh 
sudo ./gestion_fis.sh
```

**Functionality:**
This interactive script allows the administrator to:

* **Add Users:** Registers a new person in the LDAP directory and generates their Kerberos principal.
* **Delete Users:** Removes access by cleaning up both LDAP entries and Kerberos keys.
* **List Users:** Displays current members of the domain.

---

## 💻 Client Configuration

This section describes how to configure **external workstations (Clients)** to join the domain.
*These instructions are strictly for the client machines, NOT for the KDC server.*

### 🪟 Windows Clients

**Prerequisites:** *MIT Kerberos for Windows* and *PuTTY*.

* **[📄 Read the Windows Client Guide (English)](https://github.com/Al3xMR/linux-kerberos-ldap-integration/blob/main/docs/%5BENG%5Dwindows_client.md)**
* **[📄 Leer la Guía de Cliente Windows (Español)](https://github.com/Al3xMR/linux-kerberos-ldap-integration/blob/main/docs/%5BSPA%5Dwindows_client.md)**

**Overview:**
The guide explains how to configure the Network Adapter to use the KDC as the DNS server and how to set up the `krb5.ini` file.

* **Automated Script:** `client_config_scripts/windows_client.ps1` — Automatically sets the DNS, disables IPv6 to prevent conflicts, and injects the necessary registry keys for PuTTY to handle SSO.

### 🐧 Linux Clients

**Prerequisites:** *krb5-user package*.

* **[📄 Read the Linux Client Guide (English)](https://github.com/Al3xMR/linux-kerberos-ldap-integration/blob/main/docs/%5BENG%5Dlinux_client.md)**
* **[📄 Leer la Guía de Cliente Linux (Español)](https://github.com/Al3xMR/linux-kerberos-ldap-integration/blob/main/docs/%5BSPA%5Dlinux_client.md)**

**Overview:**
The guide details how to install the Kerberos client libraries and edit `/etc/resolv.conf` and `/etc/krb5.conf`.

* **Automated Script:** `client_config_scripts/ubuntu_client.sh` — Updates the system, installs dependencies, and configures the system to auto-discover the KDC via DNS SRV records.

---

**Author:** Kevin Martinez | [@Al3xMR](https://github.com/Al3xMR)

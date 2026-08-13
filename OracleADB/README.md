# Oracle Autonomous AI Database Free (ADB-Free) – Podman Manager

A menu-driven and command-line enabled Bash wrapper for running and managing the Oracle Autonomous AI Database Free container with Podman.

**Script:** `orclADBPodman.sh`  
**Current Version:** `1.3`

## Overview

`orclADBPodman.sh` provides a lightweight management interface for an Oracle Autonomous AI Database Free container used for development, testing, and MongoDB migration scenarios.

The script supports:

- Interactive menu-driven management
- Direct command-line execution for automation and scripting
- Container lifecycle management
- Oracle database user creation
- SQL access through SQLcl or SQL*Plus
- ORDS access
- Oracle AI Database API for MongoDB TLS configuration
- Oracle, root, and ADB-CLI shell access
- Container port and log visibility
- File copy into the running container
- Adaptive two-column menu layout to reduce terminal scrolling
- Single-column fallback for narrow terminals

## Requirements

- Podman installed and available in `PATH`
- Internet connectivity for the initial container image pull
- A system capable of running Oracle containers
- Acceptance of Oracle Container Registry license terms
- Valid Oracle Container Registry credentials if required
- `SYS_ADMIN` capability and access to `/dev/fuse`

## Container Image

The script uses:

```text
container-registry.oracle.com/database/adb-free:latest-26ai
```

## Port Mappings

| Host Port | Container Port | Purpose |
|---:|---:|---|
| `1521` | `1521` | Oracle Database listener |
| `1522` | `1522` | Oracle Database TLS listener |
| `8443` | `8443` | ORDS |
| `27017` | `27017` | Oracle AI Database API for MongoDB |

## Configuration

Review and modify the configuration variables near the beginning of `orclADBPodman.sh` before starting the container.

```bash
CONTAINER_NAME="myadb"
IMAGE="container-registry.oracle.com/database/adb-free:latest-26ai"

ADMIN_PASSWORD="Welcome1234!"
WALLET_PASSWORD="Welcome1234!"
WORKLOAD_TYPE="ATP"

DB_USER="matt"
DB_USER_PASSWORD="Welcome1234!"
```

`WORKLOAD_TYPE` may be configured as `ATP` or `ADW`.

> **Note:** Replace the example passwords before using the script outside of a disposable development environment. Passwords must meet the requirements of the Oracle Autonomous AI Database Free container.

### Apple Silicon / ARM

The script contains an optional platform override:

```bash
# PLATFORM="linux/amd64"
```

Uncomment this setting if an explicit `linux/amd64` platform is required.

---

## Interactive Menu

Run the script without arguments:

```bash
./orclADBPodman.sh
```

For terminals that are at least 80 columns wide, the menu is displayed in a compact two-column layout:

```text
Oracle ADB-Free Podman Manager
--------------------------------------------------------------------------------
Container Management                    Oracle AI ADB Management
--------------------                    ------------------------
1. Start ADB-Free                       9. Show Admin Info
2. Stop Container                       10. Create Database User
3. Restart Container                    11. SQL Admin Session
4. Show Ports                           12. SQL User Session
5. Show Logs                            13. Open ORDS
6. Tail Logs                            14. ORDS MongoDB API TLS
7. Copy in File
8. Quit

Shell Access                            Destroy Area
--------------------                    ------------------------
15. Oracle Shell                        18. Remove Container (DESTROYS ALL DATA)
16. Root Shell
17. ADB-CLI Shell

Choose an option:
```

On narrower terminals, the same logical sections are displayed using a compact single-column layout.

### Menu Sections

#### Container Management

General container lifecycle and operational functions:

- Start ADB-Free
- Stop Container
- Restart Container
- Show Ports
- Show Logs
- Tail Logs
- Copy in File
- Quit

#### Oracle AI ADB Management

Database and ORDS administration functions:

- Show Admin Info
- Create Database User
- SQL Admin Session
- SQL User Session
- Open ORDS
- ORDS MongoDB API TLS

#### Shell Access

Interactive shell access inside the container:

- Oracle Shell
- Root Shell
- ADB-CLI Shell

#### Destroy Area

Destructive container operations are intentionally isolated from routine management functions:

- Remove Container (**DESTROYS ALL DATA stored inside the container**)

---

## Command-Line Usage

The interactive menu can be bypassed by supplying a command-line argument.

```bash
./orclADBPodman.sh <command>
```

### Container Management

| Command | Description |
|---|---|
| `start` | Start the ADB-Free container |
| `stop` | Stop the running container |
| `restart` | Restart the existing container |
| `ports` | Show published ports and the container IP address |
| `logs` | Show the most recent container logs |
| `taillogs` | Follow the container logs |
| `copyIn` | Copy a local file into `/tmp` inside the container |
| `remove` | Remove the container and destroy data stored inside it |

Examples:

```bash
./orclADBPodman.sh start
./orclADBPodman.sh ports
./orclADBPodman.sh logs
./orclADBPodman.sh restart
./orclADBPodman.sh stop
```

### Oracle AI ADB Management

| Command | Description |
|---|---|
| `showAdminInfo` | Display configured container, database, credential, and port information |
| `createUser` | Create or configure the custom database user |
| `sqladmin` | Open a SQL session as the database administrator |
| `sqluser` | Open a SQL session as the configured custom database user |
| `ords` | Open the ORDS URL in the local browser |
| `mongoTLS` | Check, enable, or disable ORDS TLS for the MongoDB API endpoint |

Examples:

```bash
./orclADBPodman.sh showAdminInfo
./orclADBPodman.sh createUser
./orclADBPodman.sh sqladmin
./orclADBPodman.sh sqluser
./orclADBPodman.sh ords
```

### Shell Access

| Command | Description |
|---|---|
| `oracle` | Open a shell inside the container as the `oracle` user |
| `root` | Open a shell inside the container as `root` |
| `adbcli` | Launch `adb-cli` inside the container |

Examples:

```bash
./orclADBPodman.sh oracle
./orclADBPodman.sh root
./orclADBPodman.sh adbcli
```

### Help

```bash
./orclADBPodman.sh help
```

The following are also supported:

```bash
./orclADBPodman.sh -h
./orclADBPodman.sh --help
```

---

## Oracle AI Database API for MongoDB TLS

ORDS controls TLS support for the Oracle AI Database API for MongoDB endpoint through the `mongo.tls` configuration setting.

The script provides both an interactive submenu and command-line access to this setting.

### Interactive TLS Management

Select:

```text
14. ORDS MongoDB API TLS
```

The TLS submenu provides:

```text
ORDS MongoDB API TLS
--------------------
1. Check TLS status
2. Enable TLS
3. Disable TLS
4. Return to main menu
```

### Command-Line TLS Management

Check the current TLS setting:

```bash
./orclADBPodman.sh mongoTLS status
```

Enable TLS:

```bash
./orclADBPodman.sh mongoTLS enable
```

Disable TLS:

```bash
./orclADBPodman.sh mongoTLS disable
```

The script also accepts the following command aliases:

```text
mongoTLS
mongotls
mongo-tls
```

If no TLS action is specified, the command defaults to displaying the current status.

For example:

```bash
./orclADBPodman.sh mongoTLS
```

is equivalent to:

```bash
./orclADBPodman.sh mongoTLS status
```

### ORDS Commands Used

The script executes the following ORDS configuration commands inside the running container.

Check status:

```bash
ords config info mongo.tls
```

Enable TLS:

```bash
ords config set mongo.tls true
```

Disable TLS:

```bash
ords config set mongo.tls false
```

After an enable or disable operation, the script displays the resulting `mongo.tls` configuration.

---

## Database User Creation

The `createUser` function creates or configures the user defined by:

```bash
DB_USER="matt"
DB_USER_PASSWORD="Welcome1234!"
```

The function:

1. Checks whether the configured database user already exists.
2. Creates the user when necessary.
3. Applies the configured Oracle database roles and privileges.
4. Grants an unlimited quota on the `DATA` tablespace.
5. Enables the schema through ORDS.

The operation is designed to be rerunnable; an existing user is not recreated.

---

## SQL Access

### Administrator Session

Interactive menu:

```text
11. SQL Admin Session
```

Command line:

```bash
./orclADBPodman.sh sqladmin
```

### Custom User Session

Interactive menu:

```text
12. SQL User Session
```

Command line:

```bash
./orclADBPodman.sh sqluser
```

The script checks for SQLcl first and falls back to SQL*Plus when SQLcl is not available.

---

## ORDS

The ORDS endpoint is exposed on:

```text
https://localhost:8443/
```

Use the interactive menu:

```text
13. Open ORDS
```

or run:

```bash
./orclADBPodman.sh ords
```

On macOS, the script uses the `open` command to launch the URL in the default browser. On platforms where `open` is unavailable, the URL is displayed so it can be opened manually.

---

## Logs

Show the most recent 200 log lines:

```bash
./orclADBPodman.sh logs
```

Follow the logs continuously:

```bash
./orclADBPodman.sh taillogs
```

Use `Ctrl+C` to exit log-following mode.

---

## Copying Files into the Container

Run:

```bash
./orclADBPodman.sh copyIn
```

The script prompts for:

1. The absolute path containing the local file.
2. The file name.

The file is copied into:

```text
/tmp
```

inside the ADB-Free container.

---

## Removing the Container

The remove operation is intentionally separated into the **Destroy Area** of the interactive menu.

Command line:

```bash
./orclADBPodman.sh remove
```

> **Warning:** Removing the container destroys data stored inside the container unless persistent storage has been configured separately.

---

## Persistence

The default script does not configure persistent volume storage. Data stored only inside the container is lost when the container is removed.

If persistent data is required, add the appropriate Podman volume mounts before using the container for anything beyond disposable development or testing.

---

## Typical Workflow

Start the container:

```bash
./orclADBPodman.sh start
```

Verify ports:

```bash
./orclADBPodman.sh ports
```

Create the development user:

```bash
./orclADBPodman.sh createUser
```

Open a SQL session:

```bash
./orclADBPodman.sh sqluser
```

Check MongoDB API TLS configuration:

```bash
./orclADBPodman.sh mongoTLS status
```

Enable MongoDB API TLS when required:

```bash
./orclADBPodman.sh mongoTLS enable
```

View logs:

```bash
./orclADBPodman.sh logs
```

Stop the container:

```bash
./orclADBPodman.sh stop
```

---

## Notes

- The script is intended primarily for development, testing, demonstrations, and migration-related experimentation.
- Review passwords, port mappings, host mappings, capabilities, and storage configuration before use.
- The script currently starts the container with the `SYS_ADMIN` capability and `/dev/fuse`.
- The default configuration does not provide persistent storage.
- The `remove` operation permanently removes data stored only inside the container.

## License

This script is distributed under the Universal Permissive License (UPL), Version 1.0, as declared in the script header.

## Author

Matt DeMarco

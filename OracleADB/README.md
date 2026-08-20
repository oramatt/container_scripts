# Oracle Autonomous AI Database Free – Podman Manager

A Bash-based management utility for running and administering the **Oracle Autonomous AI Database Free** container with Podman.

The script provides both an interactive menu and direct command-line execution for container lifecycle management, SQL access, database-user creation, ORDS MongoDB API TLS management, shell access, logging, and optional integration with the companion Spark + Iceberg + MinIO data-lake environment.

> **Script:** `orclADBPodman.sh`  
> **Current documented version:** `1.4.0`  
> **Default image:** `container-registry.oracle.com/database/adb-free:latest-26ai`

This project is intended for local development, demonstrations, migration testing, and learning. It is not a production deployment framework.

---

## Overview

`orclADBPodman.sh` wraps common Oracle Autonomous AI Database Free container operations behind a consistent menu and CLI.

Major capabilities include:

- Pull and start the Oracle Autonomous AI Database Free 26ai container.
- Start, stop, restart, inspect, and remove the container.
- Display container ports and IP information.
- Show and follow container logs.
- Open ORDS in the local browser.
- Create and configure a non-admin database user.
- Open SQL sessions as `ADMIN` or the configured application user.
- Open Oracle, root, and `adb-cli` shells.
- Copy local files into `/tmp` in the running container.
- Check, enable, or disable ORDS TLS for the Oracle AI Database API for MongoDB.
- Provide an adaptive two-column interactive menu with a single-column fallback.
- Create or reuse a shared `oracle-datalake` Podman network.
- Integrate with `sparkIcebergManager.sh` and its MinIO S3-compatible object store.
- Synchronize the local MinIO CA from the `minio-s3-tls` container.
- Test DNS and trusted HTTPS connectivity from the ADB container to MinIO.
- Configure a `DBMS_CLOUD` credential and network ACL for MinIO.
- Execute a real `DBMS_CLOUD.LIST_OBJECTS` request against the shared `warehouse` bucket.

---

## Architecture

The ADB container can run independently or as part of a local Oracle + Spark/Iceberg data-lake lab.

### Standalone ADB-Free

```text
                          Local Host
                              |
             +----------------+----------------+
             |                |                |
             v                v                v
        SQL / TLS           ORDS          MongoDB API
       1521 / 1522          8443             27017
             \                |                /
              \               |               /
               +--------------+--------------+
                              |
                              v
                         +---------+
                         |  myadb  |
                         | ADB-Free|
                         +---------+
```

### ADB-Free + Spark/Iceberg + MinIO

When used with `sparkIcebergManager.sh` v1.2.0 or later:

```text
                           Podman
                             |
                  oracle-datalake network
                             |
              +--------------+--------------+
              |                             |
              v                             v
         +---------+                 +---------------+
         |  myadb  |                 | minio-s3-tls  |
         | ADB-Free|                 | HTTPS / S3    |
         +----+----+                 +-------+-------+
              |                              |
              | DBMS_CLOUD                   | HTTP / S3
              | s3://warehouse.minio/        |
              |                              v
              |                         +---------+
              +------------------------>|  MinIO  |
                                        +----+----+
                                             |
                                             v
                                      warehouse bucket
                                             ^
                                             |
                                      Spark / Iceberg
```

MinIO remains the authoritative object store. No NFS layer or macOS host-filesystem bridge is used for the object-storage integration.

---

## Requirements

### Required

- Podman installed and available in `PATH`.
- Internet connectivity for the initial image pull.
- Acceptance of the Oracle Container Registry license terms.
- Valid Oracle Container Registry credentials if required.
- A system capable of allocating sufficient CPU and memory to ADB-Free.

Oracle currently documents **4 CPUs and 8 GiB of memory** for the Autonomous AI Database Free container.

On macOS or Windows, configure and start the Podman machine before starting ADB-Free:

```bash
podman machine init
podman machine set --cpus 4 --memory 8192
podman machine start
```

If the Podman machine already exists:

```bash
podman machine set --cpus 4 --memory 8192
podman machine start
```

### Optional for Spark / MinIO integration

For the data-lake features:

- `sparkIcebergManager.sh` v1.2.0 or later.
- Both environments must use **Podman** so they can share the same Podman network.
- The Spark environment must provide the `minio-s3-tls` service for CA synchronization and Oracle-facing HTTPS/S3 access.

---

## Oracle ADB-Free Image

The script defaults to:

```text
container-registry.oracle.com/database/adb-free:latest-26ai
```

Oracle's current 26ai ADB-Free image supports both `linux/arm64` and `linux/amd64`, so current Apple Silicon systems can normally use the native image without emulation.

The script still supports an optional `PLATFORM` override:

```bash
export PLATFORM=linux/amd64
./orclADBPodman.sh start
```

Use a platform override only when specifically required.

---

## Default Configuration

| Setting | Default |
| --- | --- |
| Container name | `myadb` |
| Image | `container-registry.oracle.com/database/adb-free:latest-26ai` |
| Workload type | `ATP` |
| Admin password | `Welcome1234!` |
| Wallet password | `Welcome1234!` |
| Application user | `matt` |
| Application-user password | `Welcome1234!` |
| Shared data-lake network | `oracle-datalake` |
| MinIO TLS proxy | `minio-s3-tls` |
| MinIO root host | `minio` |
| MinIO bucket host | `warehouse.minio` |
| MinIO bucket | `warehouse` |
| MinIO access key | `admin` |
| MinIO secret key | `password` |
| DBMS_CLOUD credential | `DATALAKE_S3_CRED` |

These are development defaults. Change credentials before using the script anywhere other than an isolated local lab.

---

## Published Ports

| Host port | Container port | Purpose |
| ---: | ---: | --- |
| `1521` | `1521` | Oracle SQL listener |
| `1522` | `1522` | TLS database listener |
| `8443` | `8443` | ORDS, Database Actions, and APEX |
| `27017` | `27017` | Oracle AI Database API for MongoDB |

ORDS is available locally at:

```text
https://localhost:8443/
```

---

## Installation

Make the script executable:

```bash
chmod +x orclADBPodman.sh
```

Verify Podman:

```bash
podman --version
podman info
```

Display help:

```bash
./orclADBPodman.sh help
```

---

## Quick Start

Start ADB-Free:

```bash
./orclADBPodman.sh start
```

Display container and database information:

```bash
./orclADBPodman.sh showAdminInfo
```

Create the configured application user:

```bash
./orclADBPodman.sh createUser
```

Open a SQL session as the application user:

```bash
./orclADBPodman.sh sqluser
```

Open a SQL session as `ADMIN`:

```bash
./orclADBPodman.sh sqladmin
```

Stop or restart the container:

```bash
./orclADBPodman.sh stop
./orclADBPodman.sh restart
```

---

## Interactive Menu

Run the script with no command:

```bash
./orclADBPodman.sh
```

On terminals at least 80 columns wide, the menu displays related sections side-by-side. Narrower terminals automatically fall back to a single-column layout.

The menu is organized into:

### Container Management

- Start ADB-Free
- Stop Container
- Restart Container
- Show Ports
- Show Logs
- Tail Logs
- Copy in File
- Quit

### Oracle AI ADB Management

- Show Admin Info
- Create Database User
- SQL Admin Session
- SQL User Session
- Open ORDS
- ORDS MongoDB API TLS

### Shell Access

- Oracle Shell
- Root Shell
- ADB-CLI Shell

### Data Lake / MinIO

- Show Data Lake Info
- Connect / Refresh Data Lake
- Test Data Lake Connectivity
- Configure DBMS_CLOUD

### Destroy Area

- Remove Container (**DESTROYS ALL DATA stored inside the container**)

---

## Command-Line Interface

| Command | Description |
| --- | --- |
| `start` | Start ADB-Free or restart the existing container. |
| `stop` | Stop the running container. |
| `restart` | Restart the existing container. |
| `remove` | Force-remove the container. Data stored only inside the container is lost. |
| `createUser` | Create/configure the application database user and enable ORDS for the schema. |
| `showAdminInfo` | Display container, credential, port, and data-lake information. |
| `sqladmin` | Open SQLcl or SQL*Plus as `ADMIN`. |
| `sqluser` | Ensure the application user exists, then open SQLcl or SQL*Plus as that user. |
| `ports` | Show published ports and container IP information. |
| `adbcli` | Open `adb-cli` inside the container. |
| `ords` | Open the local ORDS endpoint. |
| `root` | Open a root shell inside the container. |
| `oracle` | Open an `oracle` OS-user shell inside the container. |
| `logs` | Show the latest 200 container log lines. |
| `taillogs` | Follow container logs. |
| `copyIn` | Copy a selected local file into `/tmp` in the container. |
| `mongoTLS` | Check, enable, or disable ORDS MongoDB API TLS. |
| `datalake` | Join/verify the shared network, synchronize the MinIO CA, and test HTTPS. |
| `datalakeConnect` | Alias for `datalake`. |
| `datalakeInfo` | Display the shared-network and S3 integration contract. |
| `datalakeTest` | Test DNS and trusted HTTPS from the Oracle container. |
| `datalakeCA` | Refresh the MinIO CA from `minio-s3-tls`. |
| `datalakeDB` | Configure DBMS_CLOUD ACL/credential and execute a real MinIO object listing. |
| `help`, `-h`, `--help` | Show CLI help. |

---

## Database User Creation

The default application user is:

```text
workbench
```

Create or refresh the user configuration:

```bash
./orclADBPodman.sh createUser
```

The script creates the user if required, grants the configured development roles, grants unlimited quota on `DATA`, and enables ORDS for the schema.

---

## SQL Access

Open the application-user SQL session:

```bash
./orclADBPodman.sh sqluser
```

Open an administrator SQL session:

```bash
./orclADBPodman.sh sqladmin
```

The script uses SQLcl when available and falls back to SQL*Plus.

The local service used by the script is:

```text
localhost/myatp
```

---

## ORDS and Database Actions

Open the ORDS endpoint:

```bash
./orclADBPodman.sh ords
```

Local URL:

```text
https://localhost:8443/
```

Depending on the ADB-Free image and enabled applications, ORDS provides access to services such as Database Actions and APEX.

---

## Oracle AI Database API for MongoDB TLS

Check status:

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

The corresponding ORDS configuration operations are:

```bash
ords config info mongo.tls
ords config set mongo.tls true
ords config set mongo.tls false
```

---

## Shell Access

```bash
./orclADBPodman.sh oracle
./orclADBPodman.sh root
./orclADBPodman.sh adbcli
```

---

## File Copy

Run:

```bash
./orclADBPodman.sh copyIn
```

The script prompts for an absolute local directory path and file name, then copies the file to `/tmp` inside `myadb`.

---

# Spark / Iceberg / MinIO Integration

Version 1.4.0 can interoperate directly with the companion `sparkIcebergManager.sh` v1.2.0 environment.

The objective is to let Oracle Autonomous AI Database and Spark/Iceberg access the **same MinIO object store** without NFS or a shared macOS filesystem.

## Integration Contract

| Component | Default |
| --- | --- |
| Container runtime | Podman |
| Oracle container | `myadb` |
| Shared network | `oracle-datalake` |
| TLS proxy container | `minio-s3-tls` |
| S3 root host | `minio` |
| S3 virtual bucket host | `warehouse.minio` |
| Bucket | `warehouse` |
| Access key | `admin` |
| Secret key | `password` |
| DBMS_CLOUD credential | `DATALAKE_S3_CRED` |

Oracle-facing MinIO endpoint:

```text
https://warehouse.minio:443
```

DBMS_CLOUD URI prefix:

```text
s3://warehouse.minio/
```

Spark/Iceberg continues to access MinIO through its Compose-private network.

---

## Shared Network Behavior

The Oracle manager creates or reuses:

```text
oracle-datalake
```

during `start` and `restart`.

A new Oracle container is launched directly on that network. If an existing container is not attached, the script uses `podman network connect` to attach it.

This allows either stack to be started first.

---

## Start Order

### Spark first

```bash
./sparkIcebergManager.sh start
./orclADBPodman.sh start
./orclADBPodman.sh datalakeDB
```

### Oracle first

```bash
./orclADBPodman.sh start
./sparkIcebergManager.sh start
./orclADBPodman.sh datalake
./orclADBPodman.sh datalakeDB
```

---

## Show Data-Lake Configuration

```bash
./orclADBPodman.sh datalakeInfo
```

This displays the Oracle container, shared network, TLS proxy, S3 hosts, bucket, credentials, DBMS_CLOUD credential, and CA trust path.

---

## Connect or Refresh the Data-Lake Integration

```bash
./orclADBPodman.sh datalake
```

The command performs:

```text
Create/reuse oracle-datalake
          |
          v
Attach myadb
          |
          v
Read CA from minio-s3-tls
          |
          v
Install CA into Oracle Linux trust store
          |
          v
Resolve minio / warehouse.minio
          |
          v
Validate trusted HTTPS
```

The CA is read directly from:

```text
minio-s3-tls:/etc/nginx/tls/ca.crt
```

and installed at:

```text
/etc/pki/ca-trust/source/anchors/oracle-datalake-ca.crt
```

The script runs `update-ca-trust` when available.

No host-mounted CA file is required for this exchange.

---

## Test Container-Level Connectivity

```bash
./orclADBPodman.sh datalakeTest
```

The test validates DNS resolution for `minio` and `warehouse.minio`, trusted HTTPS to the MinIO health endpoint, and TLS validation for the virtual-hosted bucket endpoint.

This proves the container/network/TLS layer. It does not by itself prove database-level DBMS_CLOUD trust.

---

## Refresh the MinIO CA

If the Spark manager regenerates TLS:

```bash
./sparkIcebergManager.sh regeneratetls
```

refresh Oracle trust:

```bash
./orclADBPodman.sh datalakeCA
```

or rerun:

```bash
./orclADBPodman.sh datalake
```

---

## Configure and Test DBMS_CLOUD

```bash
./orclADBPodman.sh datalakeDB
```

This is the end-to-end database integration test. It:

1. Ensures container-level data-lake connectivity.
2. Ensures the configured application user exists.
3. Adds an outbound network ACL for `warehouse.minio`.
4. Creates or refreshes `DATALAKE_S3_CRED` using the configured MinIO access key and secret key.
5. Executes `DBMS_CLOUD.LIST_OBJECTS` against `s3://warehouse.minio/` and displays up to 20 objects.

A successful `datalakeDB` run verifies substantially more than container-level connectivity because the S3 request originates from inside Oracle Database.

---

## Equivalent DBMS_CLOUD Configuration

### Network ACL

```sql
BEGIN
    DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
        host => 'warehouse.minio',
        ace  => xs$ace_type(
                    privilege_list => xs$name_list('http'),
                    principal_name => 'WORKBENCH',
                    principal_type => xs_acl.ptype_db
                ),
        private_target => TRUE
    );
END;
/
```

### S3-Compatible Credential

```sql
BEGIN
    DBMS_CLOUD.CREATE_CREDENTIAL(
        credential_name => 'DATALAKE_S3_CRED',
        username        => 'admin',
        password        => 'password'
    );
END;
/
```

### Object Listing

```sql
SELECT object_name,
       bytes
FROM DBMS_CLOUD.LIST_OBJECTS(
         'DATALAKE_S3_CRED',
         's3://warehouse.minio/'
     );
```

These are development defaults from the local lab. Do not reuse them for production credentials.

---

## Data-Lake Environment Overrides

| Variable | Purpose | Default |
| --- | --- | --- |
| `ORACLE_DATALAKE_NETWORK` | Shared Podman network | `oracle-datalake` |
| `SPARK_ICEBERG_NETWORK` | Fallback shared-network value | `oracle-datalake` |
| `ORACLE_DATALAKE_TLS_CONTAINER` | MinIO HTTPS proxy container | `minio-s3-tls` |
| `ORACLE_DATALAKE_S3_ROOT_HOST` | MinIO root hostname | `minio` |
| `ORACLE_DATALAKE_S3_HOST` | Virtual-hosted bucket hostname | `warehouse.minio` |
| `ORACLE_DATALAKE_BUCKET` | MinIO bucket | `warehouse` |
| `ORACLE_DATALAKE_ACCESS_KEY` | MinIO access key | `admin` |
| `ORACLE_DATALAKE_SECRET_KEY` | MinIO secret key | `password` |
| `ORACLE_DATALAKE_CREDENTIAL` | DBMS_CLOUD credential name | `DATALAKE_S3_CRED` |
| `ORACLE_DATALAKE_CA_PROXY_PATH` | CA path inside `minio-s3-tls` | `/etc/nginx/tls/ca.crt` |

Example:

```bash
export ORACLE_DATALAKE_NETWORK=oracle-datalake
export ORACLE_DATALAKE_BUCKET=warehouse
export ORACLE_DATALAKE_ACCESS_KEY=admin
export ORACLE_DATALAKE_SECRET_KEY=password

./orclADBPodman.sh datalakeDB
```

> **Note:** v1.4.0 reads `ORACLE_DATALAKE_ACCESS_KEY` and `ORACLE_DATALAKE_SECRET_KEY`. Those are the authoritative environment-variable names defined by the script.

---

## Recommended End-to-End Validation

```bash
./sparkIcebergManager.sh start
./sparkIcebergManager.sh tests3

./orclADBPodman.sh start
./orclADBPodman.sh datalakeTest
./orclADBPodman.sh datalakeDB
```

This validates Spark/MinIO access, Oracle-container DNS/TLS access, and Oracle DBMS_CLOUD S3 access.

---

## Core Script Configuration

The ADB configuration is defined near the top of `orclADBPodman.sh`:

```bash
CONTAINER_NAME="myadb"
IMAGE="container-registry.oracle.com/database/adb-free:latest-26ai"

ADMIN_PASSWORD="Welcome1234!"
WALLET_PASSWORD="Welcome1234!"
WORKLOAD_TYPE="ATP"

DB_USER="workbench"
DB_USER_PASSWORD="Welcome1234!"
```

The source comments identify `ATP` and `ADW` as workload-type options.

---

## Custom Host Mapping

The current script contains this environment-specific argument:

```bash
--add-host cloudfs.home.com:192.168.1.191
```

If that hostname/address is not part of your environment, remove or modify the line before distributing or reusing the script elsewhere.

It is unrelated to the MinIO `oracle-datalake` integration.

---

## Data Persistence

The current ADB manager does **not** configure a persistent database volume.

Therefore:

```bash
./orclADBPodman.sh remove
```

force-removes `myadb`, and data stored only inside that container is lost.

The shared `oracle-datalake` network and MinIO storage are separate resources and are not the Oracle database's persistence mechanism.

If database persistence across container recreation is required, add and validate an Oracle-supported persistent-storage configuration before relying on remove/recreate workflows.

---

## Logging

```bash
./orclADBPodman.sh logs
./orclADBPodman.sh taillogs
```

---

## Troubleshooting

### Podman is unavailable

```bash
podman info
```

On macOS or Windows:

```bash
podman machine start
```

### ADB-Free requires more resources

```bash
podman machine set --cpus 4 --memory 8192
```

Restart the Podman machine if required.

### Container does not start

```bash
./orclADBPodman.sh logs
podman ps -a
```

### A port is already in use

```bash
lsof -i :1521
lsof -i :1522
lsof -i :8443
lsof -i :27017
```

### `warehouse.minio` does not resolve

```bash
podman network inspect oracle-datalake
./orclADBPodman.sh datalake
```

### `minio-s3-tls` is not running

```bash
./sparkIcebergManager.sh start
./orclADBPodman.sh datalake
```

### HTTPS validation fails after TLS regeneration

```bash
./orclADBPodman.sh datalakeCA
./orclADBPodman.sh datalakeTest
```

### `datalakeTest` succeeds but `datalakeDB` fails

`datalakeTest` verifies container DNS and OS-level TLS trust.

`datalakeDB` verifies the actual Oracle Database `DBMS_CLOUD` request path. Review the Oracle error returned by `datalakeDB`; database-managed outbound TLS validation can be version/configuration dependent even when `curl` inside the container succeeds.

### Spark is using Docker instead of Podman

The Oracle manager is Podman-specific. Both stacks must use the same container runtime to share `oracle-datalake`.

Use:

```bash
CONTAINER_ENGINE=podman ./sparkIcebergManager.sh start
```

---

## Security Notes

This repository is designed for a local lab.

Important defaults include:

- A hard-coded ADB admin password.
- A hard-coded application-user password.
- MinIO development credentials `admin/password`.
- A private generated MinIO TLS CA.
- Root-shell access inside the ADB container.
- `SYS_ADMIN` and `/dev/fuse` capabilities.

Do not expose this configuration to an untrusted network, and do not reuse these credentials for production.

---

## Removal

```bash
./orclADBPodman.sh remove
```

The current implementation force-removes the container after warning that data stored inside it will be lost. It does not require an additional typed confirmation word, so use this command carefully.

---

## Typical Workflows

### Standalone ADB

```bash
./orclADBPodman.sh start
./orclADBPodman.sh createUser
./orclADBPodman.sh sqluser
```

### MongoDB API

```bash
./orclADBPodman.sh start
./orclADBPodman.sh mongoTLS status
./orclADBPodman.sh mongoTLS enable
```

### Spark / Iceberg / MinIO

```bash
./sparkIcebergManager.sh start
./sparkIcebergManager.sh tests3

./orclADBPodman.sh start
./orclADBPodman.sh datalake
./orclADBPodman.sh datalakeDB
```

---

## Companion Spark/Iceberg Manager

The companion Spark/Iceberg manager provides:

- Apache Spark.
- Apache Iceberg.
- Iceberg REST catalog.
- MinIO S3-compatible object storage.
- Jupyter.
- A persistent MinIO data volume.
- The `oracle-datalake` shared network.
- The `minio-s3-tls` HTTPS/S3 endpoint consumed by this script.

Use `sparkIcebergManager.sh` v1.2.0 or later with `orclADBPodman.sh` v1.4.0 or later for the integration model documented here.

---

## References

- [Oracle Autonomous AI Database Free Container](https://github.com/oracle/adb-free)
- [Oracle Autonomous AI Database Free documentation](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/autonomous-database-container-free.html)
- [Oracle DBMS_CLOUD documentation](https://docs.oracle.com/en/database/oracle/oracle-database/26/arpls/dbms_cloud.html)
- [Oracle DBMS_NETWORK_ACL_ADMIN documentation](https://docs.oracle.com/en/database/oracle/oracle-database/26/arpls/DBMS_NETWORK_ACL_ADMIN.html)
- [Podman documentation](https://docs.podman.io/)
- [MinIO documentation](https://min.io/docs/)
- [Apache Iceberg](https://iceberg.apache.org/)
- [Apache Spark](https://spark.apache.org/)

---

## Author

Matt DeMarco  
[oramatt.com](https://oramatt.com) · [github.com/oramatt](https://github.com/oramatt)

---

## License

See the license header in `orclADBPodman.sh` and the repository license terms.

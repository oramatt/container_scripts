# Spark + Iceberg Quickstart – Container Manager

A Bash-based container management utility for running the [Databricks Spark + Iceberg Quickstart](https://github.com/databricks/docker-spark-iceberg) locally with Docker or Podman, with additional MinIO persistence and Oracle Autonomous AI Database container integration.

The environment provides Apache Spark, Apache Iceberg, an Iceberg REST catalog, MinIO S3-compatible object storage, Jupyter, and Spark SQL interfaces. The manager extends the upstream quickstart with a persistent MinIO object store, a shared container network, and an Oracle-facing HTTPS/S3 endpoint suitable for local `DBMS_CLOUD` integration testing.

This is **not** a local installation or emulator of the managed Databricks platform. It is a local Spark + Iceberg development and migration lab.

## Script Name

`sparkIcebergManager.sh`

Current manager version: **1.1.0**

## Overview

The script provides both an interactive menu and a command-line interface for managing the Spark + Iceberg environment. It can:

- Detect Docker or Podman automatically.
- Clone the upstream Databricks Spark + Iceberg quickstart repository when needed.
- Start, stop, restart, update, build, and remove the environment.
- Display service status, ports, logs, credentials, and the effective Compose configuration.
- Open Jupyter, the Spark UI, the MinIO console, and the Iceberg REST endpoint.
- Launch Bash, PySpark, Spark SQL, Scala Spark, and MinIO shells.
- Run prerequisite diagnostics and HTTP health checks.
- Persist MinIO object data in a container-engine-managed named volume.
- Preserve the MinIO `warehouse` bucket across environment restarts.
- Create a shared container network for Oracle Autonomous AI Database access.
- Expose MinIO to Oracle containers through an internal HTTPS/S3 reverse proxy on port `443`.
- Generate and manage a local certificate authority and TLS server certificate for the Oracle-facing S3 endpoint.
- Test MinIO HTTPS/S3 access from the shared container network.
- Attach an existing Oracle Autonomous AI Database container to the shared network.
- Copy the generated local CA into an Oracle container and update its operating-system CA trust store when supported.

## Architecture

MinIO remains the authoritative object store. No NFS or host-filesystem gateway is used for Oracle integration.

```text
                              Host
                               |
          +--------------------+--------------------+
          |                    |                    |
          v                    v                    v
      Jupyter              Spark UI            MinIO Console
   localhost:8888       localhost:8080       localhost:9001

                         Spark / Iceberg
                               |
                               | HTTP / S3
                               v
                         +-----------+
                         |   MinIO   |
                         |   :9000   |
                         +-----------+
                               |
                               | /data
                               v
                   spark-iceberg-minio-data
                     persistent named volume

                               ^
                               |
                         HTTP / S3 :9000
                               |
                     +-----------------+
                     | minio-s3-tls    |
                     | Nginx TLS proxy |
                     | HTTPS :443      |
                     +-----------------+
                               ^
                               |
                    oracle-datalake network
                               |
                               v
                    Oracle Autonomous AI DB
                           container
```

Spark and Iceberg continue to access MinIO directly on the private Compose network:

```text
http://minio:9000
s3://warehouse/
```

An Oracle container attached to the shared `oracle-datalake` network accesses the same MinIO data through:

```text
https://warehouse.minio:443
s3://warehouse.minio/<object-name>
```

The TLS proxy stores no object data. It only provides HTTPS termination and forwards S3 requests to MinIO.

## Managed Services

| Service | Purpose | Endpoint |
| --- | --- | --- |
| Jupyter Notebook | Interactive Spark and Iceberg notebooks | <http://localhost:8888> |
| Spark UI | Spark application and job monitoring | <http://localhost:8080> |
| Iceberg REST Catalog | Local Iceberg catalog API | <http://localhost:8181> |
| MinIO API | Host-accessible S3-compatible object-storage API | <http://localhost:9000> |
| MinIO Console | Browser-based object-storage administration | <http://localhost:9001> |
| Oracle-facing MinIO S3 | HTTPS/S3 endpoint on the shared container network | `https://warehouse.minio:443` |
| Spark Thrift Server | Spark SQL Thrift/JDBC endpoint | `localhost:10000` |
| Spark Thrift HTTP | Spark Thrift HTTP transport | `localhost:10001` |

The Oracle-facing endpoint is intentionally available through the shared container network rather than through a macOS or Windows host-network workaround.

## Requirements

- Linux, macOS, or Windows with WSL2.
- Bash 4 or later.
- Git.
- OpenSSL.
- `curl` for host endpoint health checks.
- A supported container runtime:
  - [Docker](https://docs.docker.com/get-docker/) with Docker Compose v2, or
  - [Podman](https://podman.io/docs/installation) with a Compose provider.
- Internet connectivity for the initial repository clone and image pulls.
- Approximately 8 GB of available RAM is recommended for the complete stack.
- Free local ports `8080`, `8181`, `8888`, `9000`, `9001`, `10000`, and `10001`.

On macOS or Windows with Podman, start the Podman virtual machine before using the manager:

```bash
podman machine start
```

## Installation

Place `sparkIcebergManager.sh` in the directory where the upstream project checkout should be managed and make it executable:

```bash
chmod +x sparkIcebergManager.sh
```

Check prerequisites and integration configuration:

```bash
./sparkIcebergManager.sh doctor
```

Clone the upstream quickstart and generate the Oracle data-lake integration assets:

```bash
./sparkIcebergManager.sh install
```

By default, the repository is cloned into a sibling directory named `docker-spark-iceberg` unless the manager is already located in a directory containing `docker-compose.yml`.

The manager also creates integration files under:

```text
docker-spark-iceberg/.oracle-datalake/
```

## Quick Start

Start the environment:

```bash
./sparkIcebergManager.sh start
```

The start operation also ensures that the external `oracle-datalake` network exists.

Display S3 and Oracle container connection information:

```bash
./sparkIcebergManager.sh s3info
```

Test the Oracle-facing HTTPS/S3 endpoint:

```bash
./sparkIcebergManager.sh tests3
```

Open Jupyter:

```bash
./sparkIcebergManager.sh jupyter
```

Check the complete environment:

```bash
./sparkIcebergManager.sh health
```

Stop the services without removing their containers:

```bash
./sparkIcebergManager.sh stop
```

## Interactive Menu

Run the manager without an argument, or use `menu`:

```bash
./sparkIcebergManager.sh
```

```bash
./sparkIcebergManager.sh menu
```

The interactive menu is arranged into five logical areas.

### Container Management

- Install / Clone Project
- Start Environment
- Stop Environment
- Restart Environment
- Show Status
- Show Ports
- Show Logs
- Tail Logs
- Pull / Update
- Build Image

### Web Interfaces

- Open Jupyter
- Open Spark UI
- Open MinIO Console
- Open Iceberg REST
- Show Credentials
- Health Check

### MinIO / Oracle Object Storage

- Show S3 Information
- Test Oracle S3 Endpoint
- Connect Oracle Container
- Show Local CA
- Regenerate TLS
- Show Compose Config

### Shell Access

- Container Shell
- PySpark Shell
- Spark SQL Shell
- Scala Spark Shell
- MinIO Shell

### Destroy Area

- Remove Containers

The destructive action requires the exact confirmation word `REMOVE`.

## Command-Line Usage

```text
Usage: sparkIcebergManager.sh [command] [arguments]
```

| Command | Description |
| --- | --- |
| `menu` | Open the interactive menu; this is the default. |
| `install` | Clone the upstream project and prepare integration assets. |
| `start` | Start all services in the background. |
| `stop` | Stop all services without removing them. |
| `restart` | Restart the environment. |
| `status` | Show Compose service status. |
| `ports` | Show host and container-network endpoints. |
| `logs` | Show the latest service logs. |
| `tail` | Follow service logs continuously. |
| `update` | Fast-forward the upstream repository and pull current container images. |
| `pull` | Alias for `update`. |
| `build` | Build the Spark image from source. |
| `jupyter` | Open Jupyter Notebook. |
| `sparkui` | Open the Spark UI. |
| `minio` | Open the MinIO console. |
| `catalog` | Open the Iceberg REST endpoint. |
| `credentials` | Show development credentials and S3 endpoints. |
| `creds` | Alias for `credentials`. |
| `health` | Check host HTTP endpoints and Oracle-facing HTTPS/S3 access. |
| `s3info` | Show MinIO persistence, S3, TLS, and Oracle connection information. |
| `tests3` | Test HTTPS/S3 authentication and bucket access from the shared network. |
| `tests3access` | Alias for `tests3`. |
| `connectoracle <name>` | Attach an Oracle ADB container to the shared network and install the local CA. |
| `oracleconnect <name>` | Alias for `connectoracle`. |
| `cainfo` | Display the generated local CA certificate details. |
| `ca` | Alias for `cainfo`. |
| `regeneratetls` | Regenerate the local CA and TLS server certificate. |
| `tlsreset` | Alias for `regeneratetls`. |
| `shell` | Open Bash in the Spark container. |
| `pyspark` | Open a PySpark shell. |
| `sparksql` | Open a Spark SQL shell. |
| `scala` | Open a Scala Spark shell. |
| `sparkshell` | Alias for `scala`. |
| `minioshell` | Open a shell in the MinIO container. |
| `config` | Render the effective Compose configuration, including the generated override. |
| `remove` | Remove Compose containers and the project-private network while preserving MinIO object data. |
| `doctor` | Check prerequisites and integration configuration. |
| `help` | Show built-in help. |
| `version` | Show the manager version. |

## MinIO Object Storage

MinIO is the authoritative storage system for the data-lake environment.

Default settings:

| Setting | Value |
| --- | --- |
| Access key | `admin` |
| Secret key | `password` |
| Bucket | `warehouse` |
| Spark/Iceberg endpoint | `http://minio:9000` |
| Spark/Iceberg warehouse URI | `s3://warehouse/` |
| Host API | `http://localhost:9000` |
| Console | `http://localhost:9001` |
| Persistent volume | `spark-iceberg-minio-data` |

The generated Compose override mounts MinIO `/data` to the named volume. The manager also changes bucket initialization to use an idempotent create operation so the existing `warehouse` bucket is not deleted and recreated when the environment starts.

Display current storage information with:

```bash
./sparkIcebergManager.sh s3info
```

## Oracle Autonomous AI Database Container Integration

The manager creates an external container network named:

```text
oracle-datalake
```

An Oracle Autonomous AI Database container can be attached to this network without routing data through the host operating system.

For a container named `adb-free`:

```bash
./sparkIcebergManager.sh connectoracle adb-free
```

The command performs the following actions:

1. Ensures the shared `oracle-datalake` network exists.
2. Verifies that the specified Oracle container exists.
3. Attaches the Oracle container to the shared network if necessary.
4. Copies the generated local CA certificate into the Oracle container.
5. Runs `update-ca-trust` as root when that command is available in the container.
6. Tests DNS resolution of `warehouse.minio` from the Oracle container.
7. Displays the S3 endpoint, credential information, and next database-side steps.

After attachment, the Oracle-facing endpoint is:

```text
https://warehouse.minio:443
```

The corresponding S3-compatible URI pattern shown by the manager is:

```text
s3://warehouse.minio/<object-name>
```

For example:

```text
s3://warehouse.minio/oracle-export/customers.parquet
```

### What `connectoracle` Does Not Configure

The manager prepares container networking and operating-system certificate trust. It does **not** automatically create Oracle database objects.

Database-side configuration still includes, as applicable:

- Creating a `DBMS_CLOUD` credential for the MinIO access key and secret key.
- Allowing outbound access to `warehouse.minio` with the applicable Oracle network ACL configuration.
- Confirming that the database trusts the local CA for HTTPS validation.
- Performing an actual `DBMS_CLOUD` request as the final connectivity test.

The script explicitly notes that installing the CA in the container OS trust store may not by itself configure database-specific certificate trust for every Oracle version or configuration.

## Oracle-Facing HTTPS/S3 Gateway

The manager adds a small Nginx service named:

```text
minio-s3-tls
```

This service:

- Listens on HTTPS port `443` inside the container network.
- Uses the manager-generated TLS certificate.
- Preserves the original S3 `Host` header and request path.
- Proxies requests to `http://minio:9000`.
- Stores no application or object data.

It receives the shared-network aliases:

```text
minio
warehouse.minio
```

The `warehouse.minio` hostname supports the manager's Oracle-facing virtual-host-style S3 URI.

Spark and Iceberg do not need to use this TLS gateway; they continue communicating directly with MinIO over their private Compose network.

## Testing Oracle-Facing S3 Access

Run:

```bash
./sparkIcebergManager.sh tests3
```

The manager launches a temporary MinIO client container on the `oracle-datalake` network and tests:

- Shared-network DNS and connectivity.
- HTTPS access to the TLS gateway.
- MinIO S3 authentication.
- Access to the `warehouse` bucket.

The test uses the MinIO client image and the generated HTTPS endpoint. It uses the MinIO client's insecure TLS mode because the temporary client container does not import the manager's private CA.

The full health check includes this S3 test:

```bash
./sparkIcebergManager.sh health
```

## TLS and Local Certificate Authority

TLS assets are generated under:

```text
docker-spark-iceberg/.oracle-datalake/tls/
```

The important files are:

```text
ca.crt       Local CA certificate
ca.key       Local CA private key
server.crt   TLS server certificate
server.key   TLS server private key
metadata     Certificate identity metadata
```

The server certificate includes DNS names used by the container environment, including `warehouse.minio`.

Display CA details:

```bash
./sparkIcebergManager.sh cainfo
```

This shows the subject, issuer, validity period, and SHA-256 fingerprint.

### Regenerating TLS

To create a new CA and server certificate:

```bash
./sparkIcebergManager.sh regeneratetls
```

When run interactively, the manager requires the exact confirmation word:

```text
REGENERATE
```

Regenerating the CA invalidates the previous Oracle trust relationship. Any Oracle container that trusted the old CA should be reconfigured by running `connectoracle` again.

## Generated Integration Files

The manager automatically creates and maintains:

```text
docker-spark-iceberg/
├── docker-compose.yml
├── docker-compose.oracle-datalake.yml
└── .oracle-datalake/
    ├── nginx.conf
    └── tls/
        ├── ca.crt
        ├── ca.key
        ├── server.crt
        ├── server.key
        └── metadata
```

`docker-compose.oracle-datalake.yml` is generated by the manager and should not be treated as the primary hand-maintained Compose file. The `config` command renders the effective merged Compose configuration:

```bash
./sparkIcebergManager.sh config
```

## Development Credentials

The upstream quickstart defaults used by the manager are:

| Interface | Credential |
| --- | --- |
| Jupyter Notebook | No username/password; token authentication is disabled |
| MinIO access key | `admin` |
| MinIO secret key | `password` |
| MinIO bucket | `warehouse` |
| Spark UI | No authentication |
| Iceberg REST catalog | No authentication |

Display the current values and endpoints:

```bash
./sparkIcebergManager.sh credentials
```

These credentials are intended only for an isolated local development environment.

## Configuration

The manager supports the following environment variables:

| Variable | Purpose | Default |
| --- | --- | --- |
| `SPARK_ICEBERG_HOME` | Upstream project checkout directory. | `docker-spark-iceberg` beside the manager unless the current script directory already contains the Compose project. |
| `SPARK_ICEBERG_REPOSITORY_URL` | Alternate Git repository or fork. | `https://github.com/databricks/docker-spark-iceberg.git` |
| `SPARK_ICEBERG_NETWORK` | Shared Oracle/data-lake container network. | `oracle-datalake` |
| `SPARK_ICEBERG_MINIO_VOLUME` | Named volume used for MinIO `/data`. | `spark-iceberg-minio-data` |
| `SPARK_ICEBERG_TLS_PROXY_IMAGE` | Image used for the HTTPS/S3 reverse proxy. | `nginx:alpine` |
| `SPARK_ICEBERG_MC_IMAGE` | MinIO client image used for S3 testing. | `minio/mc:latest` |
| `ORACLE_ADB_CONTAINER` | Default Oracle ADB container name used by `connectoracle`. | No default |
| `CONTAINER_ENGINE` | Force a container runtime instead of automatic detection. | Automatically prefers Podman when available, otherwise Docker. |

Examples:

```bash
SPARK_ICEBERG_HOME="$PWD/labs/docker-spark-iceberg" \
  ./sparkIcebergManager.sh install
```

```bash
CONTAINER_ENGINE=docker ./sparkIcebergManager.sh start
```

```bash
CONTAINER_ENGINE=podman ./sparkIcebergManager.sh status
```

```bash
ORACLE_ADB_CONTAINER=adb-free \
  ./sparkIcebergManager.sh connectoracle
```

To persist settings for the current shell session:

```bash
export SPARK_ICEBERG_NETWORK=oracle-datalake
export SPARK_ICEBERG_MINIO_VOLUME=spark-iceberg-minio-data
export ORACLE_ADB_CONTAINER=adb-free
```

## Data Persistence

MinIO object data is persisted in a named container-engine volume:

```text
spark-iceberg-minio-data
```

This volume is mounted at `/data` in the MinIO service.

The `remove` command performs a Compose teardown but intentionally does **not** request volume deletion:

```bash
./sparkIcebergManager.sh remove
```

The manager reports that it will preserve:

- The MinIO named volume.
- The shared external `oracle-datalake` network.

This means MinIO objects survive normal manager-driven container removal and recreation as long as the named volume itself is not manually deleted with Docker or Podman.

The upstream quickstart may also contain local project directories such as notebooks or warehouse-related files. Their behavior is determined by the upstream Compose project, but MinIO persistence in this manager is specifically provided by the named MinIO volume described above.

## Removing the Environment

Run:

```bash
./sparkIcebergManager.sh remove
```

The manager requires:

```text
REMOVE
```

before proceeding.

The command removes the Compose containers and project-private network while preserving the MinIO named volume and external shared network.

To deliberately delete the persisted MinIO object store, use the appropriate Docker or Podman volume-management command separately. The manager does not perform that destructive operation.

## Updating and Building

Use `update` to fast-forward the upstream Git checkout and pull current referenced images:

```bash
./sparkIcebergManager.sh update
```

The integration assets are regenerated as part of the update flow.

Use `build` after modifying the upstream Dockerfile or when a local rebuild is required:

```bash
./sparkIcebergManager.sh build
```

Review upstream changes before updating if the cloned repository contains local modifications.

## Diagnostics

Run:

```bash
./sparkIcebergManager.sh doctor
```

The diagnostic report includes:

- Manager version.
- Project path.
- Repository URL.
- Shared network name.
- MinIO data volume name.
- Oracle S3 hostname.
- Container runtime.
- Compose provider.
- Presence of the upstream Compose file.
- Readiness of the generated Compose override.
- Readiness of TLS assets.
- Shared network state.

## Health Checks

Run:

```bash
./sparkIcebergManager.sh health
```

The health command checks host-accessible endpoints for:

- Jupyter.
- Spark UI.
- Iceberg REST.
- MinIO API health.
- MinIO Console.

It then performs a separate Oracle-facing HTTPS/S3 test from the `oracle-datalake` container network.

## Common Examples

View host and container endpoints:

```bash
./sparkIcebergManager.sh ports
```

Display MinIO and Oracle S3 details:

```bash
./sparkIcebergManager.sh s3info
```

Test Oracle-facing object storage:

```bash
./sparkIcebergManager.sh tests3
```

Attach an Oracle ADB container:

```bash
./sparkIcebergManager.sh connectoracle adb-free
```

Inspect the local CA:

```bash
./sparkIcebergManager.sh cainfo
```

Follow environment logs:

```bash
./sparkIcebergManager.sh tail
```

Open a PySpark session:

```bash
./sparkIcebergManager.sh pyspark
```

Open Spark SQL:

```bash
./sparkIcebergManager.sh sparksql
```

Render the effective Compose configuration:

```bash
./sparkIcebergManager.sh config
```

## Troubleshooting

### Container runtime is installed but unavailable

Start Docker Desktop, the Docker daemon, or the Podman machine, then run:

```bash
./sparkIcebergManager.sh doctor
```

### The shared Oracle data-lake network does not exist

The manager normally creates it automatically during `start`, `tests3`, or `connectoracle`.

To inspect the configured network name:

```bash
./sparkIcebergManager.sh s3info
```

### Oracle container cannot resolve `warehouse.minio`

Reconnect the Oracle container:

```bash
./sparkIcebergManager.sh connectoracle adb-free
```

Then verify that the container is attached to the configured shared network with the appropriate Docker or Podman inspection command.

The manager also attempts a `getent hosts warehouse.minio` check during `connectoracle`.

### Oracle HTTPS or S3 test fails

Run:

```bash
./sparkIcebergManager.sh tests3
./sparkIcebergManager.sh logs
./sparkIcebergManager.sh s3info
```

Also verify that the `minio`, `mc`, and `minio-s3-tls` services are running.

### Oracle database does not trust the HTTPS certificate

`connectoracle` installs the local CA into the container operating-system trust store when `update-ca-trust` is available. Database-specific certificate validation can still require additional configuration depending on the Oracle image/version.

Use an actual `DBMS_CLOUD` request as the final validation rather than relying only on the OS-level CA installation.

### TLS identity changed

If the Oracle-facing hostname or TLS metadata changes, the manager can regenerate certificates automatically. Existing Oracle containers may then trust an older CA.

Run:

```bash
./sparkIcebergManager.sh connectoracle adb-free
```

after regeneration to install the current CA.

### A local port is already in use

Identify and stop the conflicting process or container, or modify the applicable upstream Compose port mapping. Display expected endpoints with:

```bash
./sparkIcebergManager.sh ports
```

### Browser opening is unsupported

When the manager cannot launch a browser automatically, it prints the URL so it can be opened manually.

### Podman Compose is missing

Install a compatible Compose provider and verify one of the following:

```bash
podman compose version
```

or:

```bash
podman-compose --version
```

## Security Notes

This project is intended for an isolated development and learning environment.

Important defaults and behaviors include:

- Jupyter authentication is disabled by the upstream image.
- MinIO uses the development access key `admin` and secret key `password`.
- The generated Compose override configures anonymous public access on the `warehouse` bucket to match the quickstart's development behavior.
- The manager generates a private local CA and stores its private key under `.oracle-datalake/tls/ca.key`.
- The TLS endpoint is intended for communication between containers on the shared network.
- Published host ports may be reachable by other systems depending on the host firewall and container runtime configuration.
- The local CA, private keys, development credentials, and generated integration files should not be treated as production secrets or production PKI.
- Do not deploy this stack as a production service without redesigning authentication, authorization, TLS, secrets management, network exposure, data durability, and operational controls.

## Learning and Migration Scope

The stack is well suited for practicing:

- Spark DataFrame and SQL workflows.
- PySpark and Scala development.
- Iceberg table creation, schema evolution, partition evolution, snapshots, and time travel.
- Iceberg REST catalog interactions.
- S3-compatible object-storage concepts using MinIO.
- Persistent local object storage using a named container volume.
- Container-native data exchange between Spark/Iceberg and Oracle Autonomous AI Database.
- HTTPS/S3 connectivity for `DBMS_CLOUD` proof-of-concept work.
- Oracle-to-object-storage and object-storage-to-Oracle migration patterns.
- Notebook-driven data engineering and migration validation workflows.

Databricks-specific managed capabilities—such as workspaces, Unity Catalog governance, cluster policies, Databricks SQL warehouses, jobs, model serving, and account administration—require a Databricks workspace or another appropriate Databricks environment.

## References

- [Databricks Spark + Iceberg Quickstart](https://github.com/databricks/docker-spark-iceberg)
- [Apache Spark Documentation](https://spark.apache.org/docs/latest/)
- [Apache Iceberg Documentation](https://iceberg.apache.org/docs/latest/)
- [MinIO Documentation](https://min.io/docs/minio/container/index.html)
- [Oracle Autonomous AI Database Free Container](https://github.com/oracle/adb-free)
- [Oracle Autonomous Database DBMS_CLOUD Documentation](https://docs.oracle.com/en/database/oracle/oracle-database/26/arpls/dbms_cloud.html)

## Author

Matt DeMarco  
[oramatt.com](https://oramatt.com) · [github.com/oramatt](https://github.com/oramatt)

# Spark + Iceberg Quickstart – Container Manager

A Bash-based container management utility for running the [Databricks Spark + Iceberg Quickstart](https://github.com/databricks/docker-spark-iceberg) locally with Docker or Podman, with persistent MinIO object storage and integrated Oracle Autonomous AI Database container connectivity.

The environment provides Apache Spark, Apache Iceberg, an Iceberg REST catalog, MinIO S3-compatible object storage, Jupyter, and Spark SQL interfaces. `sparkIcebergManager.sh` extends the upstream quickstart with a persistent MinIO object store, a shared container network, an Oracle-facing HTTPS/S3 endpoint, locally managed TLS, and interoperability with `orclADBPodman.sh`.

This is **not** a local installation or emulator of the managed Databricks platform. It is a local Spark + Iceberg + MinIO development and database-modernization lab.

## Script Name

`sparkIcebergManager.sh`

Current manager version: **1.2.0**

## Overview

The script provides both an interactive menu and a command-line interface for managing the complete Spark + Iceberg environment. It can:

- Detect Docker or Podman automatically.
- Clone the upstream Databricks Spark + Iceberg quickstart repository when needed.
- Start, stop, restart, update, build, and remove the environment.
- Display service status, ports, logs, credentials, and the effective Compose configuration.
- Open Jupyter, the Spark UI, the MinIO console, and the Iceberg REST endpoint.
- Launch Bash, PySpark, Spark SQL, Scala Spark, and MinIO shells.
- Run prerequisite diagnostics and HTTP/S3 health checks.
- Persist MinIO object data in a container-engine-managed named volume.
- Preserve the MinIO `warehouse` bucket across environment restarts and Compose removal.
- Create and preserve a shared `oracle-datalake` container network.
- Expose MinIO to Oracle containers through an internal HTTPS/S3 endpoint on port `443`.
- Generate and manage a local certificate authority and TLS server certificate.
- Expose the local CA through the TLS proxy so the matching Oracle manager can synchronize trust directly between containers.
- Test the Oracle-facing S3-compatible endpoint from the shared container network.
- Attach an Oracle Autonomous AI Database container to the shared network.
- Install the generated local CA into an attached Oracle container OS trust store when supported.
- Default Oracle integration to the `myadb` container created by `orclADBPodman.sh`.
- Automatically connect a running `myadb` container when the Spark stack is started.
- Detect a Podman/Docker runtime mismatch before attempting cross-container integration.

## Architecture

MinIO remains the authoritative storage system. No NFS layer, rclone gateway, or macOS host-filesystem workaround is used for Oracle integration.

```text
                                      Host
                                       |
                 +---------------------+---------------------+
                 |                     |                     |
                 v                     v                     v
             Jupyter               Spark UI             MinIO Console
          localhost:8888        localhost:8080        localhost:9001

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
                                container: myadb
                                      |
                                      v
                                  DBMS_CLOUD
```

Spark and Iceberg continue to access MinIO directly on the private Compose network:

```text
http://minio:9000
s3://warehouse/
```

An Oracle container attached to `oracle-datalake` accesses the same MinIO data through the TLS proxy:

```text
https://warehouse.minio:443
s3://warehouse.minio/<object-name>
```

The TLS proxy stores no object data. It only terminates HTTPS and forwards S3 requests to MinIO.

## Oracle Integration Contract

Version 1.2.0 is designed to interoperate with the matching `orclADBPodman.sh` integration using these defaults:

| Setting | Default |
| --- | --- |
| Oracle container | `myadb` |
| Shared network | `oracle-datalake` |
| TLS proxy container | `minio-s3-tls` |
| MinIO root hostname | `minio` |
| MinIO bucket hostname | `warehouse.minio` |
| MinIO bucket | `warehouse` |
| MinIO access key | `admin` |
| MinIO secret key | `password` |
| Oracle-facing protocol | HTTPS/S3 |
| Oracle-facing port | `443` |
| Spark-facing MinIO endpoint | `http://minio:9000` |
| MinIO persistent volume | `spark-iceberg-minio-data` |

Both managers must use the **same container runtime**. The Oracle manager is Podman-based, so when using the two scripts together the recommended invocation is:

```bash
CONTAINER_ENGINE=podman ./sparkIcebergManager.sh start
```

A Docker network and a Podman network with the same name are still separate networks and cannot provide cross-runtime container connectivity.

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

The Oracle-facing HTTPS endpoint is internal to the shared container network. It is not published as a host port.

## Requirements

- Linux, macOS, or Windows with WSL2.
- Bash 4 or later.
- Git.
- OpenSSL.
- `curl` for host endpoint health checks.
- A supported container runtime:
  - [Docker](https://docs.docker.com/get-docker/) with Docker Compose v2, or
  - [Podman](https://podman.io/docs/installation) with a Compose provider.
- Internet connectivity for the initial repository clone and container image pulls.
- Approximately 8 GB of available RAM is recommended for the Spark/Iceberg stack; additional memory is required when running Oracle ADB at the same time.
- Free local ports `8080`, `8181`, `8888`, `9000`, `9001`, `10000`, and `10001`.

For integration with `orclADBPodman.sh`:

- Podman is recommended for both stacks.
- The Oracle container should normally be named `myadb`.
- The Oracle container should be running before `sparkIcebergManager.sh start` if you want automatic attachment during Spark startup.

On macOS or Windows with Podman, start the Podman virtual machine first:

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

By default, the repository is cloned into a sibling directory named `docker-spark-iceberg` unless the manager itself is already located in a directory containing `docker-compose.yml`.

## Generated Integration Assets

The manager generates an additional Compose override and TLS configuration without modifying the upstream Compose file directly.

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

The generated override:

- Mounts a persistent named volume at MinIO `/data`.
- Changes MinIO client initialization to create `warehouse` only if it does not already exist.
- Adds the `minio-s3-tls` Nginx service.
- Mounts `ca.crt`, `server.crt`, and `server.key` into the TLS proxy.
- Connects the TLS proxy to the private Iceberg network and the external `oracle-datalake` network.
- Adds the DNS aliases `minio` and `warehouse.minio` on `oracle-datalake`.

Do not manually edit `docker-compose.oracle-datalake.yml`; the manager regenerates it as needed.

## Quick Start

Start the environment:

```bash
./sparkIcebergManager.sh start
```

The `start` command:

1. Validates the container runtime.
2. Ensures the upstream project exists.
3. Generates or validates TLS assets.
4. Regenerates the Compose override.
5. Creates `oracle-datalake` if it does not exist.
6. Starts the Spark/Iceberg/MinIO environment.
7. Checks for the configured Oracle container, defaulting to `myadb`.
8. If that Oracle container exists and is running in the same runtime, attempts to attach it to `oracle-datalake` and install the local CA.

Display MinIO and Oracle connection information:

```bash
./sparkIcebergManager.sh s3info
```

Test the Oracle-facing HTTPS/S3 endpoint from the shared network:

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

Stop services without removing their containers:

```bash
./sparkIcebergManager.sh stop
```

## Working with `orclADBPodman.sh`

### Recommended startup order: Oracle first

Starting Oracle first allows `sparkIcebergManager.sh start` to detect `myadb` automatically.

```bash
./orclADBPodman.sh start
CONTAINER_ENGINE=podman ./sparkIcebergManager.sh start
./sparkIcebergManager.sh tests3
```

If `myadb` is running, Spark startup attempts to:

- Attach `myadb` to `oracle-datalake` if necessary.
- Copy the generated CA certificate into the Oracle container.
- Add it to the Oracle Linux OS trust store when `update-ca-trust` is available.
- Confirm that `warehouse.minio` resolves from inside the Oracle container.

### Spark first

Starting Spark first is also supported:

```bash
CONTAINER_ENGINE=podman ./sparkIcebergManager.sh start
./orclADBPodman.sh start
```

Because the Oracle container did not exist when Spark started, run either the Oracle manager's data-lake connection workflow or explicitly reconnect from the Spark manager:

```bash
./sparkIcebergManager.sh connectoracle myadb
```

The matching Oracle manager can also obtain the CA directly from the running `minio-s3-tls` container, which avoids requiring a hard-coded host filesystem path between the two scripts.

### Explicit re-sync

Use `connectoracle` whenever you need to re-establish or validate the container-level integration:

```bash
./sparkIcebergManager.sh connectoracle
```

The default container is `myadb`.

For another container name:

```bash
./sparkIcebergManager.sh connectoracle adb-free
```

Explicit re-sync is particularly useful after:

- Starting Oracle after the Spark stack.
- Recreating the Oracle container.
- Regenerating the local TLS CA.
- Changing the shared network name.
- Changing container runtimes.
- Diagnosing DNS or trust-store problems.

## Automatic Oracle Attachment Behavior

Automatic Oracle integration is performed by the `start` command.

If `myadb`:

- **Does not exist:** Spark starts normally and Oracle integration is skipped.
- **Exists but is stopped:** Spark starts normally and reports that automatic attachment was skipped.
- **Exists and is running in the same runtime:** the manager attempts `connectoracle` automatically.
- **Exists in Podman while Spark is using Docker:** the manager warns that both scripts must use the same runtime.

A simple `restart` of an already-existing Spark Compose environment restarts the Compose services but does not run the same automatic Oracle attachment logic as a fresh `start`. Use `connectoracle` explicitly if re-synchronization is needed.

## Interactive Menu

Run the manager without an argument, or use `menu`:

```bash
./sparkIcebergManager.sh
```

```bash
./sparkIcebergManager.sh menu
```

The menu is organized into five logical areas.

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
| `install` | Clone the upstream repository if needed and generate integration assets. |
| `start` | Start all services and attempt automatic Oracle attachment. |
| `stop` | Stop all Compose services without removing them. |
| `restart` | Restart existing Compose services; if none exist, fall back to `start`. |
| `status` | Show Compose service status. |
| `ports` | Show host and container-network endpoints. |
| `logs` | Show the latest service logs. |
| `tail` | Follow service logs continuously. |
| `update` | Fast-forward the upstream repository and pull current images. |
| `pull` | Alias for `update`. |
| `build` | Build the Spark image from source. |
| `jupyter` | Open Jupyter Notebook. |
| `sparkui` | Open the Spark UI. |
| `minio` | Open the MinIO console. |
| `catalog` | Open the Iceberg REST endpoint. |
| `credentials` | Show development credentials and S3 endpoints. |
| `creds` | Alias for `credentials`. |
| `health` | Check host endpoints plus Oracle-facing HTTPS/S3 access. |
| `s3info` | Show MinIO storage, TLS, and Oracle connection details. |
| `tests3` | Test HTTPS/S3 authentication and bucket access through `oracle-datalake`. |
| `tests3access` | Alias for `tests3`. |
| `connectoracle [name]` | Attach an Oracle ADB container and install the local CA; defaults to `myadb`. |
| `oracleconnect [name]` | Alias for `connectoracle`. |
| `cainfo` | Show generated local CA subject, issuer, validity, and SHA-256 fingerprint. |
| `ca` | Alias for `cainfo`. |
| `regeneratetls` | Regenerate the local CA and TLS server certificate. |
| `tlsreset` | Alias for `regeneratetls`. |
| `shell` | Open Bash in the Spark container. |
| `pyspark` | Open a PySpark shell. |
| `sparksql` | Open a Spark SQL shell. |
| `scala` | Open a Scala Spark shell. |
| `sparkshell` | Alias for `scala`. |
| `minioshell` | Open a shell in the MinIO container. |
| `config` | Render the effective Compose configuration. |
| `remove` | Remove Compose containers while preserving MinIO object data and the shared network. |
| `doctor` | Check prerequisites and integration configuration. |
| `help` | Show built-in help. |
| `version` | Show the manager version. |

## Common Examples

Show current endpoints:

```bash
./sparkIcebergManager.sh ports
```

Display the MinIO/Oracle integration contract:

```bash
./sparkIcebergManager.sh s3info
```

Verify the S3 gateway before connecting Oracle:

```bash
./sparkIcebergManager.sh tests3
```

Connect the default Oracle container:

```bash
./sparkIcebergManager.sh connectoracle
```

Connect a specifically named Oracle container:

```bash
./sparkIcebergManager.sh connectoracle myadb
```

Show the local CA:

```bash
./sparkIcebergManager.sh cainfo
```

Open a PySpark session:

```bash
./sparkIcebergManager.sh pyspark
```

Open Spark SQL:

```bash
./sparkIcebergManager.sh sparksql
```

Render the merged upstream and Oracle-data-lake Compose configuration:

```bash
./sparkIcebergManager.sh config
```

## Development Credentials

The upstream quickstart uses development credentials that this manager preserves:

| Interface | Username / Access key | Password / Secret key |
| --- | --- | --- |
| Jupyter Notebook | None | None; token authentication is disabled |
| MinIO Console | `admin` | `password` |
| S3-compatible API | `admin` | `password` |

The default bucket is:

```text
warehouse
```

Display all relevant connection information with:

```bash
./sparkIcebergManager.sh credentials
```

These credentials are intended only for an isolated development environment.

## S3 Addressing

### Spark / Iceberg

Spark and Iceberg use the private Compose endpoint:

```text
Endpoint: http://minio:9000
Warehouse: s3://warehouse/
```

### Oracle container

Oracle uses the shared network and TLS proxy:

```text
Network:      oracle-datalake
HTTPS:        https://warehouse.minio:443
S3 URI:       s3://warehouse.minio/<object-name>
Root endpoint https://minio:443
```

Example object path:

```text
s3://warehouse.minio/oracle-export/customers.parquet
```

The same object is stored in the MinIO `warehouse` bucket and is visible to Spark through the corresponding warehouse key.

## S3 Endpoint Test

The `tests3` command launches a temporary MinIO client container on `oracle-datalake` and validates:

- Shared-network DNS resolution.
- HTTPS connectivity to the TLS proxy.
- S3 authentication with `admin/password`.
- Access to the `warehouse` bucket.

Run:

```bash
./sparkIcebergManager.sh tests3
```

The test intentionally uses the MinIO client with `--insecure` because its purpose is to validate the generated endpoint and S3 behavior before Oracle trust is configured. Oracle itself should be configured to trust the generated CA rather than bypass certificate verification.

## TLS and Local Certificate Authority

The manager generates a local CA with a long-lived CA certificate and a server certificate for the Oracle-facing endpoint.

The server certificate includes these DNS identities:

```text
warehouse.minio
minio
minio-s3-tls
localhost
```

View CA information:

```bash
./sparkIcebergManager.sh cainfo
```

The TLS proxy receives:

```text
/etc/nginx/tls/server.crt
/etc/nginx/tls/server.key
/etc/nginx/tls/ca.crt
```

The CA certificate is deliberately available inside `minio-s3-tls` so the matching Oracle manager can copy the trust anchor directly from the running proxy container.

### Regenerating TLS

To replace the CA and server certificate:

```bash
./sparkIcebergManager.sh regeneratetls
```

Interactive execution requires the exact confirmation word:

```text
REGENERATE
```

Regenerating the CA invalidates prior Oracle trust. After regeneration, reconnect or re-synchronize every Oracle container that trusted the previous CA:

```bash
./sparkIcebergManager.sh connectoracle myadb
```

The script restarts the TLS proxy when it is already running so the new certificate is loaded.

## Oracle Container Trust Installation

`connectoracle` copies the generated CA into the target container at:

```text
/tmp/oracle-datalake-ca.crt
```

When `update-ca-trust` is available, it then installs the CA as root under:

```text
/etc/pki/ca-trust/source/anchors/oracle-datalake-ca.crt
```

and runs:

```text
update-ca-trust
```

This configures the **container operating-system trust store**.

Database-side `DBMS_CLOUD` certificate validation can depend on the Autonomous Database image and configuration. A successful OS trust update is therefore not by itself proof that `DBMS_CLOUD` can complete an HTTPS request. Use an actual database-side request as the final validation step.

## DBMS_CLOUD Integration

After the container-level connection succeeds, the database-side workflow is conceptually:

1. Create a `DBMS_CLOUD` credential using the MinIO access key and secret key.
2. Configure the applicable database network ACL for `warehouse.minio`.
3. Issue a real `DBMS_CLOUD` request against an object URI such as:

```text
s3://warehouse.minio/oracle-export/customers.parquet
```

The matching `orclADBPodman.sh` can automate or assist with these database-side checks. `sparkIcebergManager.sh` is responsible for the Spark/MinIO network, TLS, S3 endpoint, and container trust handoff.

## Configuration

The manager supports the following environment variables:

| Variable | Purpose | Default |
| --- | --- | --- |
| `SPARK_ICEBERG_HOME` | Upstream project checkout directory. | `docker-spark-iceberg` beside the manager unless the script directory already contains `docker-compose.yml`. |
| `SPARK_ICEBERG_REPOSITORY_URL` | Alternate upstream repository or fork. | `https://github.com/databricks/docker-spark-iceberg.git` |
| `SPARK_ICEBERG_NETWORK` | Shared Oracle/S3 network. | `oracle-datalake` |
| `SPARK_ICEBERG_MINIO_VOLUME` | Persistent MinIO named volume. | `spark-iceberg-minio-data` |
| `SPARK_ICEBERG_TLS_PROXY_IMAGE` | TLS reverse-proxy image. | `nginx:alpine` |
| `SPARK_ICEBERG_MC_IMAGE` | MinIO client image used for S3 tests. | `minio/mc:latest` |
| `ORACLE_ADB_CONTAINER` | Default Oracle ADB container used by automatic and explicit integration. | `myadb` |
| `CONTAINER_ENGINE` | Forces Docker or Podman. | Auto-detects Podman first, then Docker. |

Examples:

```bash
SPARK_ICEBERG_HOME="$PWD/labs/docker-spark-iceberg" \
  ./sparkIcebergManager.sh install
```

Use Podman explicitly for interoperability with `orclADBPodman.sh`:

```bash
CONTAINER_ENGINE=podman ./sparkIcebergManager.sh start
```

Use a different Oracle container:

```bash
ORACLE_ADB_CONTAINER=adb-free \
CONTAINER_ENGINE=podman \
  ./sparkIcebergManager.sh start
```

Use a different shared network:

```bash
SPARK_ICEBERG_NETWORK=my-datalake \
  ./sparkIcebergManager.sh start
```

When changing the network name, the Oracle manager must use the same value.

## MinIO Data Persistence

MinIO `/data` is mounted to the named volume:

```text
spark-iceberg-minio-data
```

The generated Compose override defines:

```text
minio-data -> spark-iceberg-minio-data
```

This makes MinIO the persistent system of record for the object-storage portion of the lab.

The manager also replaces the upstream MinIO-client bucket initialization behavior with an idempotent operation equivalent to:

```text
mc mb --ignore-existing minio/warehouse
```

so an existing `warehouse` bucket is retained across starts.

### `remove` behavior

```bash
./sparkIcebergManager.sh remove
```

removes the Compose containers and project-private network, but preserves:

- `spark-iceberg-minio-data`
- `oracle-datalake`
- generated integration assets under `.oracle-datalake/`

The command does **not** use Compose `-v`, so the MinIO named volume is not deleted.

The exact confirmation word is:

```text
REMOVE
```

If data is important beyond the scope of this development lab, maintain independent backups.

## Updating and Building

Update the upstream Git checkout and pull current images:

```bash
./sparkIcebergManager.sh update
```

The manager regenerates its integration assets after the source update.

Build the Spark image from source:

```bash
./sparkIcebergManager.sh build
```

Review upstream changes before updating if you maintain local changes inside the cloned repository.

## Diagnostics

Run:

```bash
./sparkIcebergManager.sh doctor
```

The diagnostic output includes:

- Manager version.
- Project path.
- Upstream repository URL.
- Shared network name.
- MinIO named volume.
- Oracle S3 hostname.
- Default Oracle container name.
- Selected container runtime.
- Compose provider.
- Presence of the upstream Compose file.
- Readiness of the generated Compose override.
- Readiness of local TLS assets.
- Current shared-network existence.

## Health Checks

Run:

```bash
./sparkIcebergManager.sh health
```

The manager checks host-facing endpoints for:

- Jupyter.
- Spark UI.
- Iceberg REST.
- MinIO API health.
- MinIO Console.

It then performs a separate container-network S3 test against the Oracle-facing HTTPS endpoint.

## Troubleshooting

### Oracle container does not connect automatically

Automatic connection occurs during `start` and only when the configured Oracle container is already running.

Check:

```bash
podman ps --format '{{.Names}}'
```

Then explicitly connect:

```bash
./sparkIcebergManager.sh connectoracle myadb
```

### Oracle is in Podman but Spark is using Docker

The two environments cannot share a container network across runtimes.

Start Spark using Podman:

```bash
CONTAINER_ENGINE=podman ./sparkIcebergManager.sh start
```

### `warehouse.minio` does not resolve inside Oracle

Confirm network membership:

```bash
podman network inspect oracle-datalake
```

Then re-run:

```bash
./sparkIcebergManager.sh connectoracle myadb
```

### Oracle HTTPS/S3 test fails

Check:

```bash
./sparkIcebergManager.sh status
./sparkIcebergManager.sh logs
./sparkIcebergManager.sh s3info
./sparkIcebergManager.sh tests3
```

Confirm that `minio-s3-tls` and MinIO are running.

### Oracle still rejects the TLS certificate

First verify the OS-level trust installation by re-running:

```bash
./sparkIcebergManager.sh connectoracle myadb
```

Then inspect the CA:

```bash
./sparkIcebergManager.sh cainfo
```

If container-level HTTPS works but a database-side `DBMS_CLOUD` request fails certificate validation, additional database-specific certificate trust configuration may be required by that ADB image/version.

### TLS was regenerated

The previous CA is no longer valid for existing Oracle trust relationships.

Run:

```bash
./sparkIcebergManager.sh connectoracle myadb
```

or use the matching Oracle manager's CA synchronization function.

### MinIO data appears to be missing

Check that the configured named volume still exists:

```bash
podman volume inspect spark-iceberg-minio-data
```

or with Docker:

```bash
docker volume inspect spark-iceberg-minio-data
```

Also verify `SPARK_ICEBERG_MINIO_VOLUME` has not been changed between runs.

### Container runtime is installed but unavailable

For Podman on macOS or Windows:

```bash
podman machine start
```

Then:

```bash
./sparkIcebergManager.sh doctor
```

### A host port is already in use

Check the required endpoints:

```bash
./sparkIcebergManager.sh ports
```

The Oracle-facing HTTPS/S3 port `443` is internal to `oracle-datalake` and is not a host port reservation.

### Podman Compose is missing

Verify either:

```bash
podman compose version
```

or:

```bash
podman-compose --version
```

## Security Notes

- Jupyter authentication is disabled by the upstream image.
- MinIO uses fixed development credentials: `admin/password`.
- The manager sets anonymous access on the quickstart `warehouse` bucket to preserve the upstream development behavior.
- The generated CA private key is stored locally under `.oracle-datalake/tls/ca.key` and must be treated as sensitive.
- The Oracle-facing TLS endpoint is intended only for the local shared container network.
- The TLS proxy does not store data; MinIO remains the authoritative object store.
- Installing the local CA into an Oracle container extends that container's OS trust store to certificates issued by this local development CA.
- Regenerating TLS changes the trust anchor and requires Oracle trust synchronization again.
- Published host ports may be reachable from other systems depending on firewall and container-runtime configuration.
- This configuration is for isolated development, learning, and migration prototyping—not production deployment.

## Learning and Migration Scope

This stack is well suited for practicing:

- Spark DataFrame and SQL workflows.
- PySpark and Scala development.
- Iceberg table creation and querying.
- Iceberg schema and partition evolution.
- Iceberg snapshots and time-travel concepts.
- REST catalog interactions.
- S3-compatible object-storage workflows using MinIO.
- Persistent object-storage handling in a local container lab.
- Oracle Autonomous AI Database data-lake integration.
- `DBMS_CLOUD`-oriented S3 migration patterns.
- Bidirectional Oracle-to-object-store and object-store-to-Oracle migration experiments.
- Container-native DNS, network, TLS, and trust relationships between independent application stacks.

Databricks-specific managed services such as workspaces, Unity Catalog governance, cluster policies, Databricks SQL warehouses, managed jobs, model serving, and account administration require a real Databricks environment.

## Suggested End-to-End Validation

For the matching Spark and Oracle managers, a useful validation sequence is:

```bash
./orclADBPodman.sh start

CONTAINER_ENGINE=podman ./sparkIcebergManager.sh start
./sparkIcebergManager.sh tests3
./sparkIcebergManager.sh connectoracle myadb

./orclADBPodman.sh datalakeTest
./orclADBPodman.sh datalakeDB
```

This progressively validates:

```text
Spark/Iceberg -> MinIO
Container network -> MinIO HTTPS/S3
Oracle container -> warehouse.minio
Oracle OS trust -> local CA
Oracle DBMS_CLOUD -> MinIO S3
```

The final `DBMS_CLOUD` test is the authoritative validation that the database itself can use the local S3-compatible endpoint.

## References

- [Databricks Spark + Iceberg Quickstart](https://github.com/databricks/docker-spark-iceberg)
- [Apache Spark documentation](https://spark.apache.org/docs/latest/)
- [Apache Iceberg documentation](https://iceberg.apache.org/docs/latest/)
- [MinIO documentation](https://min.io/docs/minio/container/index.html)
- [Oracle Autonomous AI Database Free container](https://github.com/oracle/adb-free)
- [Oracle DBMS_CLOUD documentation](https://docs.oracle.com/en/database/oracle/oracle-database/26/arpls/dbms_cloud.html)

## Author

Matt DeMarco  
[oramatt.com](https://oramatt.com) · [github.com/oramatt](https://github.com/oramatt)

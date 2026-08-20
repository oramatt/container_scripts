# Spark + Iceberg Quickstart – Container Manager

A Bash-based container management utility for running the [Databricks Spark + Iceberg Quickstart](https://github.com/databricks/docker-spark-iceberg) locally with Docker or Podman.

This environment is useful for learning Apache Spark, Apache Iceberg, REST catalogs, object storage, and notebook-based data engineering workflows. It is not a local installation or emulator of the managed Databricks platform.

## Script Name

`sparkIcebergManager.sh`

## Overview

The script provides both an interactive menu and command-line interface for managing the complete Spark + Iceberg Compose environment. It can:

- Detect Docker or Podman automatically.
- Clone the upstream Databricks quickstart repository when needed.
- Start, stop, restart, update, build, and remove the environment.
- Display service status, published ports, logs, credentials, and the resolved Compose configuration.
- Open Jupyter, the Spark UI, the MinIO console, and the Iceberg REST endpoint.
- Launch Bash, PySpark, Spark SQL, Scala Spark, and MinIO shells.
- Run prerequisite diagnostics and HTTP health checks.
- Preserve bind-mounted notebooks and warehouse data when containers are removed.

## Managed Services

| Service | Purpose | Local endpoint |
| --- | --- | --- |
| Jupyter Notebook | Interactive Spark and Iceberg notebooks | <http://localhost:8888> |
| Spark UI | Spark application and job monitoring | <http://localhost:8080> |
| Iceberg REST Catalog | Local Iceberg catalog API | <http://localhost:8181> |
| MinIO API | S3-compatible object-storage API | <http://localhost:9000> |
| MinIO Console | Browser-based object-storage administration | <http://localhost:9001> |
| Spark Thrift Server | JDBC/ODBC-compatible SQL endpoint | `localhost:10000` |
| Spark Connect | Remote Spark client endpoint | `localhost:10001` |

## Requirements

- Linux, macOS, or Windows with WSL2.
- Bash 4 or later.
- Git.
- `curl` for endpoint health checks.
- A supported container runtime:
  - [Docker](https://docs.docker.com/get-docker/) with Docker Compose v2, or
  - [Podman](https://podman.io/docs/installation) with a Compose provider.
- Approximately 8 GB of available RAM is recommended for the complete stack.
- Free local ports `8080`, `8181`, `8888`, `9000`, `9001`, `10000`, and `10001`.

On macOS or Windows with Podman, start the Podman virtual machine before using the manager:

```bash
podman machine start
```

## Installation

Place `sparkIcebergManager.sh` in the directory where you want the upstream project checkout to be managed, then make it executable:

```bash
chmod +x sparkIcebergManager.sh
```

Check the local prerequisites:

```bash
./sparkIcebergManager.sh doctor
```

Clone the upstream environment:

```bash
./sparkIcebergManager.sh install
```

By default, the repository is cloned into a sibling directory named `docker-spark-iceberg`.

## Quick Start

Start the environment:

```bash
./sparkIcebergManager.sh start
```

Open Jupyter Notebook:

```bash
./sparkIcebergManager.sh jupyter
```

Check container and endpoint health:

```bash
./sparkIcebergManager.sh health
```

Stop the services without removing their containers:

```bash
./sparkIcebergManager.sh stop
```

## Interactive Menu

Run the script without an argument, or pass `menu`:

```bash
./sparkIcebergManager.sh
```

```bash
./sparkIcebergManager.sh menu
```

The menu groups actions into four areas:

- **Container Management:** install, start, stop, restart, status, ports, logs, update, and build.
- **Web Interfaces:** Jupyter, Spark UI, MinIO, Iceberg REST, credentials, and health checks.
- **Shell Access:** Bash, PySpark, Spark SQL, Scala Spark, MinIO, and Compose configuration.
- **Destroy Area:** remove the Compose containers and network after explicit confirmation.

## Command-Line Usage

```text
Usage: sparkIcebergManager.sh [command]
```

| Command | Description |
| --- | --- |
| `menu` | Open the interactive menu; this is the default. |
| `install` | Clone the upstream repository if it is not present. |
| `start` | Start all services in the background. |
| `stop` | Stop all services without removing them. |
| `restart` | Restart the environment. |
| `status` | Show Compose service status. |
| `ports` | Show local ports and endpoints. |
| `logs` | Show the latest service logs. |
| `tail` | Follow service logs continuously. |
| `update` | Fast-forward the repository and pull container images. |
| `pull` | Alias for `update`. |
| `build` | Build the Spark image from source. |
| `jupyter` | Open Jupyter Notebook in the default browser. |
| `sparkui` | Open the Spark UI. |
| `minio` | Open the MinIO console. |
| `catalog` | Open the Iceberg REST endpoint. |
| `credentials` | Show the local development credentials. |
| `creds` | Alias for `credentials`. |
| `health` | Check container state and HTTP endpoints. |
| `shell` | Open Bash in the Spark container. |
| `pyspark` | Open a PySpark shell. |
| `sparksql` | Open a Spark SQL shell. |
| `scala` | Open a Scala Spark shell. |
| `sparkshell` | Alias for `scala`. |
| `minioshell` | Open a shell in the MinIO container. |
| `config` | Render the effective Compose configuration. |
| `remove` | Remove Compose containers and the network while preserving local data. |
| `doctor` | Check prerequisites and configuration. |
| `help` | Show built-in help. |
| `version` | Show the manager version. |

## Common Examples

View the available endpoints and ports:

```bash
./sparkIcebergManager.sh ports
```

Follow logs from the full environment:

```bash
./sparkIcebergManager.sh tail
```

Open a PySpark session configured for the environment:

```bash
./sparkIcebergManager.sh pyspark
```

Open Spark SQL:

```bash
./sparkIcebergManager.sh sparksql
```

Pull upstream changes and refreshed images:

```bash
./sparkIcebergManager.sh update
```

Render the final Compose configuration, including overrides and environment substitutions:

```bash
./sparkIcebergManager.sh config
```

## Development Credentials

The upstream quickstart uses local development credentials:

| Interface | Username | Password |
| --- | --- | --- |
| Jupyter Notebook | None | None; token authentication is disabled |
| MinIO Console | `admin` | `password` |
| S3-compatible API | Access key: `admin` | Secret key: `password` |

Display the credentials from the manager at any time:

```bash
./sparkIcebergManager.sh credentials
```

These defaults are intended only for an isolated local learning environment. Do not expose these services to an untrusted network.

## Configuration

The script supports the following environment variables:

| Variable | Purpose | Default behavior |
| --- | --- | --- |
| `SPARK_ICEBERG_HOME` | Sets the upstream project checkout directory. | Uses `docker-spark-iceberg` beside the manager script unless the script directory already contains the Compose project. |
| `SPARK_ICEBERG_REPOSITORY_URL` | Uses an alternate Git repository or fork. | `https://github.com/databricks/docker-spark-iceberg.git` |
| `CONTAINER_ENGINE` | Forces the container runtime. | Automatically detects `podman` or `docker`. |

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

To make a setting persistent for the current shell session:

```bash
export SPARK_ICEBERG_HOME="$PWD/docker-spark-iceberg"
export CONTAINER_ENGINE=docker
```

## Data Persistence

The upstream Compose project bind-mounts local directories into the Spark container:

- `notebooks/` stores notebook content.
- `warehouse/` stores local Iceberg warehouse data.

The `remove` command runs Compose teardown for the containers and network, but does not delete these bind-mounted directories:

```bash
./sparkIcebergManager.sh remove
```

The manager requires the exact confirmation word `REMOVE` before proceeding. Back up notebooks or datasets separately if they are important.

## Updating and Building

Use `update` to fast-forward the upstream Git checkout and pull the latest referenced images:

```bash
./sparkIcebergManager.sh update
```

Use `build` when you have modified the upstream Dockerfile or want to rebuild locally:

```bash
./sparkIcebergManager.sh build
```

Review upstream changes before updating if you maintain local modifications in the cloned repository.

## Troubleshooting

### Container runtime is installed but unavailable

Start Docker Desktop, the Docker service, or the Podman machine, then run:

```bash
./sparkIcebergManager.sh doctor
```

### A port is already in use

Identify the conflicting process or container, stop it, or update the port mapping in the upstream `docker-compose.yml`. The `ports` command shows every port expected by this stack:

```bash
./sparkIcebergManager.sh ports
```

### A web interface does not respond

Check service state, endpoint health, and recent logs:

```bash
./sparkIcebergManager.sh status
./sparkIcebergManager.sh health
./sparkIcebergManager.sh logs
```

The Spark UI may not show an active application until Spark work is running.

### Browser opening is unsupported

The manager prints the URL when it cannot launch a browser automatically. Copy the displayed URL into a local browser.

### Podman Compose is missing

Install a compatible Compose provider and verify that one of these commands works:

```bash
podman compose version
```

```bash
podman-compose --version
```

## Security Notes

- Jupyter authentication is disabled by the upstream image.
- MinIO uses publicly documented development credentials.
- Published ports may be reachable by other systems depending on the host firewall and container runtime configuration.
- Use this stack only on a trusted development machine and do not deploy it as a production service.
- The manager does not modify the upstream authentication or network settings.

## Learning Scope

This stack is well suited for practicing:

- Spark DataFrame and SQL workflows.
- PySpark and Scala development.
- Iceberg table creation, schema evolution, partition evolution, and snapshot queries.
- REST catalog interactions.
- S3-compatible object-storage concepts using MinIO.
- Notebook-driven data engineering.

Databricks-specific managed capabilities—such as workspaces, Unity Catalog governance, cluster policies, Databricks SQL warehouses, jobs, model serving, and account administration—require a Databricks workspace or an official Databricks training environment.

## References

- [Databricks Spark + Iceberg Quickstart](https://github.com/databricks/docker-spark-iceberg)
- [Apache Spark documentation](https://spark.apache.org/docs/latest/)
- [Apache Iceberg documentation](https://iceberg.apache.org/docs/latest/)
- [MinIO documentation](https://min.io/docs/minio/container/index.html)

## Author

Matt DeMarco  
[oramatt.com](https://oramatt.com) · [github.com/oramatt](https://github.com/oramatt)

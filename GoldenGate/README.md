# GG4MongoDB.sh - Container Management Script for Oracle GoldenGate MongoDB

This script simplifies managing an Oracle GoldenGate for MongoDB container on systems using Podman. It supports both interactive menu-driven and command-line interface (CLI) modes.

## Features

- Pull latest GoldenGate MongoDB container image
- Start or restart container with configuration options
- Stop container (without removing it)
- Remove container if needed
- Show container status and port mappings
- Interactive TUI fallback for menu-based navigation
- CLI command support for automation

## Requirements

- [Podman](https://podman.io/) installed and configured
- Internet access to pull images from Oracle Container Registry
- License agreement acceptance for container (https://container-registry.oracle.com/ords/ocr/ba/goldengate/goldengate-mongodb-migrations) 
- Script executable:  
  ```bash
  chmod +x GG4MongoDB.sh
  ```

## Usage

### Command-Line Interface

You can pass a supported command to bypass the menu:

```bash
./GG4MongoDB.sh [command]
```

### Supported Commands:

| Command   | Description                             |
|-----------|-----------------------------------------|
| `pull`    | Pulls the latest GoldenGate MongoDB image |
| `start`   | Starts or restarts the container         |
| `stop`    | Stops the running container              |
| `status`  | Displays current container ports and IP  |
| `remove`  | Removes the container                    |
| `help`    | Displays usage instructions              |

### Interactive Menu Mode

If no argument is passed, the script launches a menu interface:

```
1) Pull latest GoldenGate image
2) Start container
3) Stop container
4) Show container status
5) Remove container
6) Exit
```

## Runbook

### Pull Image

Pulls the latest GoldenGate MongoDB container image from Oracle:

```bash
./GG4MongoDB.sh pull
```

### Start Container

Starts the container using environment variables:

```bash
./GG4MongoDB.sh start
```

- If the container exists but is not running, it is restarted.
- If it is already running, the ports and IP are displayed.

### Stop Container

Stops the container without removing it:

```bash
./GG4MongoDB.sh stop
```

### Remove Container

Deletes the container (must be stopped first):

```bash
./GG4MongoDB.sh remove
```

### Show Status

Displays open ports and container IP:

```bash
./GG4MongoDB.sh status
```

## Configuration

You can modify default variables inside the script such as:

```bash
CONTAINER_NAME="ogg-mongo"
IMAGE="container-registry.oracle.com/goldengate/goldengate-mongodb-migrations:latest"
CONTAINER_PORT_MAP="-p 8081:80 -p 8443:443 -p 9443:8443"
```

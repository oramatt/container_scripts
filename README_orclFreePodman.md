# Oracle Free Database Container Management Script (`orclFreePodman.sh`)

This Bash script automates lifecycle management of an Oracle Free Database container using **Podman**. It offers CLI and interactive menu interfaces for starting, stopping, removing, and inspecting the container.

---

## Features

- Pull Oracle Free Database container image
- Start or restart the container based on user input
- Stop the container without removal
- Remove the container explicitly
- Show mapped container ports and internal IP address
- Create and manage a Podman volume for persistent data
- Create a bridged Podman network for container isolation
- Interactive menu for simplified management
- CLI argument support for automation and scripting

---

## Requirements

- Podman installed
- Internet access to pull the container image
- Sufficient system resources (as recommended by Oracle for the Free DB image)

---

## Usage

### CLI Mode

```bash
./orclFreePodman.sh pull         # Pull the Oracle DB image
./orclFreePodman.sh start        # Start or restart the container
./orclFreePodman.sh stop         # Stop the running container (without removal)
./orclFreePodman.sh remove       # Remove the container
./orclFreePodman.sh status       # Show container ports and IP address
./orclFreePodman.sh help         # Show usage instructions
```

### Interactive Menu (no argument)

```bash
./orclFreePodman.sh
```

This presents a menu with options to pull, start, stop, remove, inspect, or exit.

---

### New Features (Recently Added)

The script has been updated to include:

- Option to constrain memory and CPU allocation for the container

Please refer to the top of the script to configure these options.

## Configuration

### Customizing Global Variables

The script uses a set of configurable global variables at the top. You may edit these directly in the script before running:

```bash
# Global variables
ORACLE_USER="matt"                  # Database user
ORACLE_PASS="matt"                  # Password for the ORACLE_USER
ORACLE_SYS_PASS="Oradoc_db1"        # SYS password for administrative operations
ORACLE_CONTAINER="Oracle_DB_Container"  # Name of the container instance
ORACLE_PDB="FREEPDB1"               # Pluggable Database name
NETWORK_NAME="demonet"              # Name of the Podman network
CONTAINER_PORT_MAP="-p 1521:1521 -p 5902:5902 -p 5500:5500 -p 8080:8080 -p 8443:8443 -p 27017:27017"
MAX_INVALID=3                       # Max invalid menu attempts before exiting
INVALID_COUNT=0                     # Internal tracking of menu retries
```

These settings allow for environment-specific adjustments without changing script logic.

---

## Examples

Start and connect:

```bash
./orclFreePodman.sh start
```

View container info:

```bash
./orclFreePodman.sh status
```

Stop and delete the container:

```bash
./orclFreePodman.sh stop
./orclFreePodman.sh remove
```

---

## Notes

- If the container already exists, the script will prompt to restart or recreate it.
- A dedicated Podman bridge network (`demonet`) ensures isolated communication between containers if needed.

---

## License

This script is provided as-is. For the Oracle Free Database container image licensing, please refer to Oracle Container Registry terms.


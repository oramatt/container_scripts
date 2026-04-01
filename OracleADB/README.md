# Oracle Autonomous Database Free (ADB-Free) – Podman Manager

A simple, menu-driven and CLI-enabled wrapper script for running and managing the **Oracle Autonomous Database Free container** using Podman.

Script Name:
orclADBPodman.sh

## Overview

This script provides:
- Interactive menu-driven interface
- Command-line (non-interactive) execution
- Automatic user creation
- SQL access via SQLcl or SQL*Plus
- Container lifecycle management
- Port visibility and logging

## Requirements

- Podman installed and available in PATH
- Internet connectivity
- System capable of running Oracle containers

## Container Details

Image:
container-registry.oracle.com/database/adb-free:latest-26ai

Ports:
- 1521 -> 1522 (SQL)
- 1522 -> 1522 (TLS)
- 8443 -> 8443 (ORDS)
- 27017 -> 27017 (MongoDB API)

## Usage

Start:
./orclADBPodman.sh start

SQL Session:
./orclADBPodman.sh sqluser

Stop:
./orclADBPodman.sh stop

Remove:
./orclADBPodman.sh remove

## Configuration

ADMIN_PASSWORD="YourStrongPassword123!"
WALLET_PASSWORD="YourWalletPassword123!"
DB_USER="youruser"
DB_USER_PASSWORD="yourpassword"
ORACLE_PDB="myatp"

## Notes

- Passwords must be at least 16 characters
- Data is not persisted unless volumes are added
- Requires SYS_ADMIN and /dev/fuse

## Author

Matt DeMarco

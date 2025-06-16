#!/bin/bash
# 
#
#
#===================================================================================
#
#         FILE: GG4MongoDB.sh 
#
#        USAGE: ./GG4MongoDB.sh [pull|start|status|stop|restart|remove|help]
#
#  DESCRIPTION: Wrapper script with menu for managing Oracle GoldenGate for MongoDB Migrations
#      OPTIONS: See menu or command line arguments
# REQUIREMENTS: Podman, internet connection, OCR license agreement
#       AUTHOR: Matt DeMarco (matthew.demarco@oracle.com)
#      CREATED: 06.09.2025
#      VERSION: 1.0
#
#===================================================================================

# Copyright (c) 2025 Oracle and/or its affiliates.

# The Universal Permissive License (UPL), Version 1.0

# Subject to the condition set forth below, permission is hereby granted to any
# person obtaining a copy of this software, associated documentation and/or data
# (collectively the "Software"), free of charge and under any and all copyright
# rights in the Software, and any and all patent rights owned or freely
# licensable by each licensor hereunder covering either (i) the unmodified
# Software as contributed to or provided by such licensor, or (ii) the Larger
# Works (as defined below), to deal in both

# (a) the Software, and
# (b) any piece of software and/or hardware listed in the lrgrwrks.txt file if
# one is included with the Software (each a "Larger Work" to which the Software
# is contributed by such licensors),

# without restriction, including without limitation the rights to copy, create
# derivative works of, display, perform, and distribute the Software and make,
# use, sell, offer for sale, import, export, have made, and have sold the
# Software and the Larger Work(s), and to sublicense the foregoing rights on
# either these or other terms.

# This license is subject to the following condition:
# The above copyright notice and either this complete permission notice or at
# a minimum a reference to the UPL must be included in all copies or
# substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.



# Modify as needed
IMAGE="container-registry.oracle.com/goldengate/goldengate-mongodb-migrations:latest"
CONTAINER_NAME="ogg-mongo"
PLATFORM="linux/amd64"
NETWORK_NAME="demonet"
# -p HOSTPORT:CONTAINERPORT
CONTAINER_PORT_MAP="-p 8100:80 -p 4433:443 -p 9443:8443"


# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color


#===========================
# Helper Functions
#===========================

logInfo() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

logWarning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

logError() {
    echo -e "${RED}[ERROR]${NC} $1"
}

logSuccess() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}


# Create podman network if it doesn't exist
function createPodnet() {
    if ! podman network inspect $NETWORK_NAME &>/dev/null; then
        logInfo "Creating podman network '$NETWORK_NAME'..."
        podman network create -d bridge $NETWORK_NAME
    else
        logInfo "Podman network '$NETWORK_NAME' already exists."
    fi
}

function pullImage() {
    logInfo "Pulling Oracle GoldenGate for MongoDB Migrations image..."
    podman pull "$IMAGE"
}

function runContainer() {
    if podman container exists "$CONTAINER_NAME"; then
        logWarning "Container '$CONTAINER_NAME' already exists."

        if podman inspect -f '{{.State.Running}}' "$CONTAINER_NAME" | grep -q true; then
            logInfo "Container is already running."
            listPorts
            return
        fi

        echo "Options:"
        echo "1) Restart the container"
        echo "2) Remove and recreate it"
        echo "3) Abort"
        read -p "Choose [1-3]: " opt

        case "$opt" in
            1) restartContainer; return ;;
            2)
                logInfo "Removing existing container..."
                podman rm "$CONTAINER_NAME" &>/dev/null
                logSuccess "Old container removed."
                ;;
            *) logInfo "Aborting container start."; return ;;
        esac
    fi

    read -p "Enter OGG_ADMIN username [default: matt]: " admin
    read -s -p "Enter OGG_ADMIN password [default: Oradoc_db1]: " password
    echo

    export OGG_ADMIN="${admin:-matt}"
    export OGG_ADMIN_PWD="${password:-Oradoc_db1}"

    echo "Starting container..."
    if podman run --platform=$PLATFORM -d --name "$CONTAINER_NAME" --network "$NETWORK_NAME" $CONTAINER_PORT_MAP \
        -e OGG_ADMIN="$OGG_ADMIN" -e OGG_ADMIN_PWD="$OGG_ADMIN_PWD" "$IMAGE"; then
        listPorts
        logInfo "Container '$CONTAINER_NAME' started."
        logInfo "GoldenGate Studio access at http://localhost:9443"
    else
        logError "Failed to start container."
    fi
}

function stop_container() {
    logWarning "Stopping container '$CONTAINER_NAME'..."
    podman stop "$CONTAINER_NAME"
    logWarning "Container '$CONTAINER_NAME' stopped."
}

function restartContainer() {
    logInfo "Restarting existing container '$CONTAINER_NAME'..."
    podman stop "$CONTAINER_NAME"
    podman start "$CONTAINER_NAME"
    listPorts
    logSuccess "Container '$CONTAINER_NAME' restarted."
}

function remove_container() {
    if podman container exists "$CONTAINER_NAME"; then
        logWarning "Removing container '$CONTAINER_NAME'..."
        podman rm "$CONTAINER_NAME"
        logWarning "Container '$CONTAINER_NAME' removed."
    else
        logWarning "Container '$CONTAINER_NAME' does not exist."
    fi
}

function container_status() {
    podman ps -a --filter "name=$CONTAINER_NAME"
    listPorts
}

function getContainerId() {
    export ggRunning=$(podman ps --no-trunc --format "table {{.ID}}\t {{.Names}}\t" | grep -i $CONTAINER_NAME | awk '{print $2}')
    echo $ggRunning
}

function listPorts() {
    container_id=$(getContainerId)
    if [ -n "$container_id" ]; then
        logInfo "Container ports: $CONTAINER_NAME" 
        podman port "$container_id"

        logInfo "Container IP address: $CONTAINER_NAME" 
        podman inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container_id"

        logInfo "Oracle GoldenGate admin user: $OGG_ADMIN"
        logInfo "Oracle GoldenGate admin password: $OGG_ADMIN_PWD"
    else
        logError "No running container found."
    fi
}

# Get bash access to container
bashAccess() {
    # export orclImage=$(getContainerId)
    
    if [ -z "$CONTAINER_NAME" ]; then
        logError "No running container found."
        return 1
    fi
    
    logInfo "Opening bash shell in container..."
    podman exec -it $CONTAINER_NAME /bin/bash
}

function menu() {
    while true; do
        echo -e "${CYAN} --------------------------------------------- ${NC}"
        echo -e "${CYAN} Oracle GoldenGate for MongoDB Migrations Menu ${NC}"
        echo -e "${CYAN} --------------------------------------------- ${NC}"
        echo -e "${GREEN} 1. Pull Image ${NC}"
        echo -e "${GREEN} 2. Run Container ${NC}"
        echo -e "${GREEN} 3. Show Container Status ${NC}"
        echo -e "${RED} 4. Stop Container ${NC}"
        echo -e "${RED} 5. Remove Container ${NC}"
        echo -e "${RED} 6. Exit ${NC}"
        echo -e "${CYAN} --------------------------------------------- ${NC}"
        read -p "Choose an option [1-6]: " opt

        case $opt in
            1) pullImage ;;
            2) runContainer ;;
            3) container_status ;;
            4) stop_container ;;
            5) remove_container ;;
            6) exit 0 ;;
            7) bashAccess ;; # hidden option
            *) echo "Invalid option. Please choose again." ;;
        esac
    done
}

# Process arguments to bypass the menu
case "$1" in
    "pull")
        pullImage
        exit 0
        ;;
    "start")
        runContainer
        exit 0
        ;;
    "status")
        container_status
        exit 0
        ;;
    "stop")
        stop_container
        exit 0
        ;;
    "restart")
        restartContainer
        exit 0
        ;;
    "remove")
        remove_container
        exit 0
        ;;
    "help")
        echo "Help should be here 🤷 ..."
        exit 0
        ;;
    "bash")
        bashAccess
        exit 0
        ;;
    *)
        logError "Invalid argument, starting menu..."
        menu
        ;;
esac

# Run the menu
menu

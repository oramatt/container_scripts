#!/usr/bin/env bash

################################################################################
# Oracle Autonomous AI Database Free – Podman Runner
#
# FILE:
#   orclADBPodman.sh
#
# USAGE:
#   ./orclADBPodman.sh [start|stop|restart|remove|mongoTLS|datalake|datalakeDB|help]
#
# DESCRIPTION:
#   Wrapper script with both interactive menu and command-line bypass options
#   for managing an Oracle Autonomous AI Database Free container used for MongoDB migrations.
#
# FEATURES:
#   - Pull Oracle Autonomous AI Database Free container image
#   - Start container with required environment variables
#   - Check running container status
#   - Stop running container
#   - Restart existing container
#   - Remove container
#   - Interactive menu-driven execution
#   - Direct command-line bypass support
#   - Check, enable, or disable ORDS TLS for the Oracle AI Database API for MongoDB
#   - Compact adaptive two-column interactive menu to reduce terminal scrolling
#   - Logical menu sections for container, database, shell, data lake, and destructive operations
#   - Create or reuse the shared oracle-datalake container network
#   - Start and restart ADB-Free attached to the Spark/MinIO shared network
#   - Synchronize the MinIO local CA directly from the minio-s3-tls container
#   - Test Oracle-container DNS and HTTPS connectivity to MinIO
#   - Configure a DBMS_CLOUD S3 credential and network ACL for the application user
#   - Test DBMS_CLOUD object listing against the MinIO warehouse bucket
#
# REQUIREMENTS:
#   - Podman installed and available in PATH
#   - Internet connectivity for initial image pull
#   - Acceptance of Oracle container registry license terms
#   - Valid Oracle Container Registry credentials if required
#   - sparkIcebergManager.sh v1.2.0 or later for automatic MinIO/TLS integration
#
# NOTES:
#   - Intended for testing Oracle Autonomous AI Database Free
#   - Review port mappings, volume mounts, and environment variables before use
#   - Persistent storage should be configured if container data must survive removal
#   - MinIO remains the authoritative object store; no host filesystem or NFS bridge is used
#   - The shared data-lake network defaults to oracle-datalake
#   - The Oracle-facing MinIO endpoint defaults to https://warehouse.minio:443
#
# AUTHOR:
#   Matt DeMarco (matthew.demarco@oracle.com)
#
# CREATED:
#   04.01.2026
#
# VERSION:
#   1.4.0
################################################################################

# Copyright (c) 2026 Oracle and/or its affiliates.

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

set -u

CONTAINER_NAME="myadb"
IMAGE="container-registry.oracle.com/database/adb-free:latest-26ai"

# Required env vars
ADMIN_PASSWORD="Welcome1234!"
WALLET_PASSWORD="Welcome1234!"
WORKLOAD_TYPE="ATP"   # ATP or ADW

# Custom non-admin database user
DB_USER="matt"
DB_USER_PASSWORD="Welcome1234!"

SCRIPT_VERSION="1.4.0"

# Spark / Iceberg / MinIO data-lake integration
# These defaults intentionally match sparkIcebergManager.sh.
DATALAKE_NETWORK="${ORACLE_DATALAKE_NETWORK:-${SPARK_ICEBERG_NETWORK:-oracle-datalake}}"
DATALAKE_TLS_CONTAINER="${ORACLE_DATALAKE_TLS_CONTAINER:-minio-s3-tls}"
DATALAKE_S3_ROOT_HOST="${ORACLE_DATALAKE_S3_ROOT_HOST:-minio}"
DATALAKE_S3_HOST="${ORACLE_DATALAKE_S3_HOST:-warehouse.minio}"
DATALAKE_BUCKET="${ORACLE_DATALAKE_BUCKET:-warehouse}"
DATALAKE_ACCESS_KEY="${ORACLE_DATALAKE_ACCESS_KEY:-admin}"
DATALAKE_SECRET_KEY="${ORACLE_DATALAKE_SECRET_KEY:-password}"
DATALAKE_CREDENTIAL="${ORACLE_DATALAKE_CREDENTIAL:-DATALAKE_S3_CRED}"
DATALAKE_CA_PROXY_PATH="${ORACLE_DATALAKE_CA_PROXY_PATH:-/etc/nginx/tls/ca.crt}"
DATALAKE_CA_TMP_PATH="/tmp/oracle-datalake-ca.crt"
DATALAKE_CA_CONTAINER_PATH="/etc/pki/ca-trust/source/anchors/oracle-datalake-ca.crt"

# Uncomment on Apple Silicon / ARM if needed
# PLATFORM="linux/amd64"

# Oracle-documented port map
CONTAINER_PORT_ARGS=(
  -p 1521:1521
  -p 1522:1522
  -p 8443:8443
  -p 27017:27017
)

# Colors
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
NC="\033[0m"

logInfo()  { echo -e "${GREEN}[INFO]${NC}    $1"; }
logWarn()  { echo -e "${YELLOW}[WARN]${NC}    $1"; }
logError() { echo -e "${RED}[ERROR]${NC}   $1"; }

requirePodman() {
    if ! command -v podman >/dev/null 2>&1; then
        logError "podman is not installed or not in PATH."
        exit 1
    fi
}

ensureDataLakeNetwork() {
    requirePodman

    if podman network inspect "${DATALAKE_NETWORK}" >/dev/null 2>&1; then
        return 0
    fi

    logInfo "Creating shared data-lake network: ${DATALAKE_NETWORK}"
    if podman network create "${DATALAKE_NETWORK}" >/dev/null; then
        logInfo "Shared data-lake network created."
    else
        logError "Failed to create shared data-lake network: ${DATALAKE_NETWORK}"
        return 1
    fi
}

containerOnDataLakeNetwork() {
    local networks_json

    containerExists || return 1
    networks_json="$(podman inspect -f '{{json .NetworkSettings.Networks}}' "${CONTAINER_NAME}" 2>/dev/null)" || return 1
    [[ "${networks_json}" == *\"${DATALAKE_NETWORK}\"* ]]
}

connectDataLakeNetwork() {
    requirePodman
    ensureDataLakeNetwork || return 1

    if ! containerExists; then
        logWarn "Oracle container does not exist yet; it will join ${DATALAKE_NETWORK} when created."
        return 0
    fi

    if containerOnDataLakeNetwork; then
        logInfo "${CONTAINER_NAME} is already attached to ${DATALAKE_NETWORK}."
        return 0
    fi

    logInfo "Attaching ${CONTAINER_NAME} to ${DATALAKE_NETWORK}..."
    if podman network connect "${DATALAKE_NETWORK}" "${CONTAINER_NAME}"; then
        logInfo "${CONTAINER_NAME} attached to ${DATALAKE_NETWORK}."
    else
        logError "Failed to attach ${CONTAINER_NAME} to ${DATALAKE_NETWORK}."
        return 1
    fi
}

dataLakeTLSContainerRunning() {
    podman ps --format "{{.Names}}" | grep -q "^${DATALAKE_TLS_CONTAINER}$"
}

syncDataLakeCA() {
    requirePodman

    if ! containerRunning; then
        logError "Oracle container is not running."
        return 1
    fi

    if ! dataLakeTLSContainerRunning; then
        logWarn "${DATALAKE_TLS_CONTAINER} is not running; MinIO CA synchronization is deferred."
        logWarn "Start sparkIcebergManager.sh, then run: $0 datalake"
        return 1
    fi

    logInfo "Synchronizing MinIO CA from ${DATALAKE_TLS_CONTAINER} into ${CONTAINER_NAME}."

    if ! podman exec "${DATALAKE_TLS_CONTAINER}" sh -lc \
        "test -r '${DATALAKE_CA_PROXY_PATH}'"; then
        logError "CA certificate not found in ${DATALAKE_TLS_CONTAINER}: ${DATALAKE_CA_PROXY_PATH}"
        return 1
    fi

    if ! podman exec "${DATALAKE_TLS_CONTAINER}" cat "${DATALAKE_CA_PROXY_PATH}" | \
         podman exec -i --user 0 "${CONTAINER_NAME}" sh -lc \
         "cat > '${DATALAKE_CA_TMP_PATH}'"; then
        logError "Failed to copy the MinIO CA between containers."
        return 1
    fi

    if podman exec --user 0 "${CONTAINER_NAME}" sh -lc \
        'command -v update-ca-trust >/dev/null 2>&1'; then
        if podman exec --user 0 "${CONTAINER_NAME}" sh -lc \
            "cp '${DATALAKE_CA_TMP_PATH}' '${DATALAKE_CA_CONTAINER_PATH}' && update-ca-trust"; then
            logInfo "MinIO CA installed in the Oracle container OS truststore."
        else
            logError "Failed to update the Oracle container OS truststore."
            return 1
        fi
    else
        logWarn "update-ca-trust is unavailable; CA remains at ${DATALAKE_CA_TMP_PATH}."
        return 1
    fi
}

showDataLakeInfo() {
    echo
    echo "Oracle / Spark Data Lake Integration"
    echo "------------------------------------"
    echo "Oracle Container       : ${CONTAINER_NAME}"
    echo "Shared Network         : ${DATALAKE_NETWORK}"
    echo "TLS Proxy Container    : ${DATALAKE_TLS_CONTAINER}"
    echo "S3 Root Host           : https://${DATALAKE_S3_ROOT_HOST}:443"
    echo "S3 Bucket Host         : https://${DATALAKE_S3_HOST}:443"
    echo "DBMS_CLOUD URI         : s3://${DATALAKE_S3_HOST}/<object-name>"
    echo "Bucket                 : ${DATALAKE_BUCKET}"
    echo "Access Key             : ${DATALAKE_ACCESS_KEY}"
    echo "Secret Key             : ${DATALAKE_SECRET_KEY}"
    echo "DBMS_CLOUD Credential  : ${DATALAKE_CREDENTIAL}"
    echo "CA Trust Path          : ${DATALAKE_CA_CONTAINER_PATH}"
    echo
}

testDataLakeConnection() {
    requirePodman

    if ! containerRunning; then
        logError "Oracle container is not running."
        return 1
    fi

    local failed=0

    if podman exec "${CONTAINER_NAME}" sh -lc \
        "getent hosts '${DATALAKE_S3_ROOT_HOST}' >/dev/null 2>&1"; then
        logInfo "DNS resolves ${DATALAKE_S3_ROOT_HOST}."
    else
        logError "DNS does not resolve ${DATALAKE_S3_ROOT_HOST}."
        failed=1
    fi

    if podman exec "${CONTAINER_NAME}" sh -lc \
        "getent hosts '${DATALAKE_S3_HOST}' >/dev/null 2>&1"; then
        logInfo "DNS resolves ${DATALAKE_S3_HOST}."
    else
        logError "DNS does not resolve ${DATALAKE_S3_HOST}."
        failed=1
    fi

    if podman exec "${CONTAINER_NAME}" sh -lc 'command -v curl >/dev/null 2>&1'; then
        if podman exec "${CONTAINER_NAME}" sh -lc \
            "curl --silent --show-error --fail --max-time 10 --cacert '${DATALAKE_CA_CONTAINER_PATH}' 'https://${DATALAKE_S3_ROOT_HOST}/minio/health/live' >/dev/null"; then
            logInfo "Trusted HTTPS connection to the MinIO health endpoint succeeded."
        else
            logError "Trusted HTTPS connection to MinIO failed."
            failed=1
        fi

        # A request to the bucket host may return an application-level HTTP status,
        # but curl still verifies DNS and TLS when --fail is omitted.
        if podman exec "${CONTAINER_NAME}" sh -lc \
            "curl --silent --show-error --max-time 10 --cacert '${DATALAKE_CA_CONTAINER_PATH}' -o /dev/null 'https://${DATALAKE_S3_HOST}/'"; then
            logInfo "TLS validation for the virtual-hosted bucket endpoint succeeded."
        else
            logError "TLS validation for ${DATALAKE_S3_HOST} failed."
            failed=1
        fi
    else
        logWarn "curl is not available inside ${CONTAINER_NAME}; skipped HTTPS validation."
    fi

    return "${failed}"
}

configureDataLakeConnection() {
    requirePodman
    ensureDataLakeNetwork || return 1
    connectDataLakeNetwork || return 1

    if ! containerRunning; then
        logWarn "Oracle container is not running; network configuration is ready."
        return 0
    fi

    syncDataLakeCA || return 1
    testDataLakeConnection
}

configureDataLakeDatabase() {
    requirePodman

    if ! containerRunning; then
        logError "Oracle container is not running."
        return 1
    fi

    configureDataLakeConnection || return 1
    createUser || return 1

    logInfo "Granting ${DB_USER} HTTPS access to ${DATALAKE_S3_HOST}."

    if ! podman exec -i "${CONTAINER_NAME}" bash -lc "sqlplus -s /nolog" <<EOF
connect admin/"${ADMIN_PASSWORD}"@localhost/myatp
whenever sqlerror exit failure

begin
    DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
        host => '${DATALAKE_S3_HOST}',
        ace  => xs\$ace_type(
                    privilege_list => xs\$name_list('http'),
                    principal_name => upper('${DB_USER}'),
                    principal_type => xs_acl.ptype_db
                ),
        private_target => TRUE
    );
exception
    when others then
        if sqlcode != -24243 then
            raise;
        end if;
end;
/
exit
EOF
    then
        logError "Failed to configure the database network ACL."
        return 1
    fi

    logInfo "Creating or refreshing ${DATALAKE_CREDENTIAL} for ${DB_USER}."

    if ! podman exec -i "${CONTAINER_NAME}" bash -lc "sqlplus -s /nolog" <<EOF
connect ${DB_USER}/"${DB_USER_PASSWORD}"@localhost/myatp
whenever sqlerror exit failure

declare
    v_count number;
begin
    select count(*)
      into v_count
      from user_credentials
     where credential_name = upper('${DATALAKE_CREDENTIAL}');

    if v_count > 0 then
        DBMS_CLOUD.DROP_CREDENTIAL('${DATALAKE_CREDENTIAL}');
    end if;

    DBMS_CLOUD.CREATE_CREDENTIAL(
        credential_name => '${DATALAKE_CREDENTIAL}',
        username        => '${DATALAKE_ACCESS_KEY}',
        password        => '${DATALAKE_SECRET_KEY}'
    );
end;
/

set pagesize 100
set linesize 200
column object_name format a100
select object_name, bytes
  from DBMS_CLOUD.LIST_OBJECTS(
           '${DATALAKE_CREDENTIAL}',
           's3://${DATALAKE_S3_HOST}/'
       )
 fetch first 20 rows only;

exit
EOF
    then
        logError "DBMS_CLOUD MinIO configuration or object listing failed."
        logWarn "Container networking and OS TLS may still be correct; inspect the database error above."
        return 1
    fi

    logInfo "DBMS_CLOUD successfully authenticated to the MinIO ${DATALAKE_BUCKET} bucket."
}

autoConfigureDataLake() {
    ensureDataLakeNetwork || return 1
    connectDataLakeNetwork || return 1

    if containerRunning && dataLakeTLSContainerRunning; then
        if syncDataLakeCA; then
            testDataLakeConnection || logWarn "Data-lake network is attached, but connectivity validation reported an issue."
        fi
    elif containerRunning; then
        logInfo "Data-lake network is attached. Start sparkIcebergManager.sh to enable MinIO TLS/CA synchronization."
    fi

    return 0
}

getContainerId() {
    podman ps -q --filter "name=^${CONTAINER_NAME}$"
}

containerExists() {
    podman ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"
}

containerRunning() {
    podman ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"
}

countDown() {
    local msg="$1"
    local sec="$2"
    echo -e "${GREEN}${msg}${NC}"
    while [ "$sec" -gt 0 ]; do
        printf "  Continuing in %02d seconds...\r" "$sec"
        sleep 1
        sec=$((sec - 1))
    done
    echo ""
}

listPorts() {
    local container_id
    container_id="$(getContainerId)"
    if [ -n "$container_id" ]; then
        logInfo "Container ports:"
        podman port "$container_id"
        logInfo "Container IP address:"
        podman inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container_id"
    else
        logError "No running container found."
    fi
}

showAdminInfo() {
    echo
    echo "Container Name      : ${CONTAINER_NAME}"
    echo "Image               : ${IMAGE}"
    echo "Workload Type       : ${WORKLOAD_TYPE}"
    echo "Admin Username      : admin"
    echo "Admin Password      : ${ADMIN_PASSWORD}"
    echo "Wallet Password     : ${WALLET_PASSWORD}"
    echo "Database User       : ${DB_USER}"
    echo "Database User Pass  : ${DB_USER_PASSWORD}"
    echo
    echo "ORDS URL            : https://localhost:8443/"
    echo "Listener Port       : 1521 -> container 1521"
    echo "TLS Port            : 1522 -> container 1522"
    echo "MongoDB Port        : 27017"
    echo
    echo "Data Lake Network   : ${DATALAKE_NETWORK}"
    echo "MinIO S3 Host       : https://${DATALAKE_S3_HOST}:443"
    echo "MinIO Bucket        : ${DATALAKE_BUCKET}"
    echo "DBMS_CLOUD URI      : s3://${DATALAKE_S3_HOST}/<object-name>"
    echo
}

showLogs() {
    requirePodman
    if containerExists; then
        podman logs --tail 200 "${CONTAINER_NAME}"
    else
        logError "Container does not exist."
    fi
}

tailLogs() {
    requirePodman
    if containerExists; then
        podman logs -f --tail 200 "${CONTAINER_NAME}"
    else
        logError "Container does not exist."
    fi
}

openORDS() {
    if command -v open >/dev/null 2>&1; then
        open "https://localhost:8443/"
    else
        echo "Open https://localhost:8443/ in your browser."
    fi
}

adbCLI() {
    requirePodman
    if containerRunning; then
        logInfo "Launching adb-cli inside container..."
        podman exec -it "${CONTAINER_NAME}" adb-cli
    else
        logError "Container is not running."
    fi
}

rootAccess() {
    requirePodman
    if containerRunning; then
        logInfo "Launching root shell inside container..."
        if podman exec -it --user root "${CONTAINER_NAME}" /bin/bash 2>/dev/null; then
            return 0
        fi
        podman exec -it --user root "${CONTAINER_NAME}" /bin/sh
    else
        logError "Container is not running."
    fi
}

oracleAccess() {
    requirePodman
    if containerRunning; then
        logInfo "Launching oracle shell inside container..."
        if podman exec -it --user oracle "${CONTAINER_NAME}" /bin/bash 2>/dev/null; then
            return 0
        fi
        podman exec -it --user oracle "${CONTAINER_NAME}" /bin/sh
    else
        logError "Container is not running."
    fi
}

createUser() {
    requirePodman

    if ! containerRunning; then
        logError "Container is not running."
        return 1
    fi

    logInfo "Creating database user: ${DB_USER}"

    podman exec -i "${CONTAINER_NAME}" bash -lc "sqlplus -s /nolog" <<EOF
connect admin/"${ADMIN_PASSWORD}"@localhost/myatp
whenever sqlerror exit failure

declare
    v_count number;
begin
    select count(*)
      into v_count
      from dba_users
     where username = upper('${DB_USER}');

    if v_count = 0 then
        execute immediate 'create user ${DB_USER} identified by "${DB_USER_PASSWORD}"';
    end if;
end;
/
grant connect, resource, db_developer_role, pdb_dba, dwrole, console_developer, graph_developer to ${DB_USER};
alter user ${DB_USER} quota unlimited on data;
begin
    ords_admin.enable_schema(
        p_enabled => true,
        p_schema => upper('${DB_USER}'),
        p_url_mapping_type => 'BASE_PATH',
        p_url_mapping_pattern => lower('${DB_USER}'),
        p_auto_rest_auth => false
    );
    commit;
end;
/
exit
EOF

    if [ $? -eq 0 ]; then
        logInfo "User ${DB_USER} created or already exists, grants applied, quota set, and ORDS enabled."
    else
        logError "Failed to create user ${DB_USER}."
        return 1
    fi
}

sqlPlusUser() {
    requirePodman

    if ! containerRunning; then
        logError "Oracle container is not running."
        return 1
    fi

    createUser || return 1

    logInfo "Opening SQL session as ${DB_USER}..."

    podman exec -it "${CONTAINER_NAME}" bash -lc "
        source /home/oracle/.bashrc 2>/dev/null || true
        if command -v sql >/dev/null 2>&1; then
            sql ${DB_USER}/${DB_USER_PASSWORD}@localhost/myatp
        elif command -v sqlplus >/dev/null 2>&1; then
            sqlplus ${DB_USER}/${DB_USER_PASSWORD}@localhost/myatp
        else
            echo 'Neither sql nor sqlplus was found inside the container.'
            exit 1
        fi
    "
}

sqlPlusAdmin() {
    requirePodman

    if ! containerRunning; then
        logError "Oracle container is not running."
        return 1
    fi

    #createUser || return 1

    logInfo "Opening SQL session as Admin..."

    podman exec -it "${CONTAINER_NAME}" bash -lc "
        source /home/oracle/.bashrc 2>/dev/null || true
        if command -v sql >/dev/null 2>&1; then
            sql admin/${ADMIN_PASSWORD}@localhost/myatp
        elif command -v sqlplus >/dev/null 2>&1; then
            sqlplus admin/${ADMIN_PASSWORD}@localhost/myatp
        else
            echo 'Neither sql nor sqlplus was found inside the container.'
            exit 1
        fi
    "
}

copyIn() {
    requirePodman

    if ! containerRunning; then
        logError "Oracle container is not running."
        return 1
    fi

    read -p "Enter ABSOLUTE PATH to the file to be copied: " thePath
    read -p "Enter FILE NAME you want copied: " theFile

    logInfo "Copying file: ${thePath}/${theFile}"
    podman cp "${thePath}/${theFile}" "${CONTAINER_NAME}:/tmp"

}

restartContainer() {
    requirePodman
    ensureDataLakeNetwork || return 1

    if containerExists; then
        connectDataLakeNetwork || return 1
        logInfo "Restarting container..."
        if ! podman restart "${CONTAINER_NAME}"; then
            logError "Failed to restart container."
            return 1
        fi
        countDown "Waiting for Oracle services to come up" 10
        autoConfigureDataLake
        listPorts
        openORDS
    else
        logError "Container does not exist."
    fi
}

startContainer() {
    requirePodman
    ensureDataLakeNetwork || return 1

    if containerRunning; then
        logWarn "Container already running."
        autoConfigureDataLake
        listPorts
        #openORDS
        return 0
    fi

    if containerExists; then
        connectDataLakeNetwork || return 1
        logInfo "Existing container found. Restarting..."
        if ! podman restart "${CONTAINER_NAME}"; then
            logError "Failed to restart container."
            return 1
        fi
        countDown "Waiting for Oracle services to come up" 10
        autoConfigureDataLake
        listPorts
        #openORDS
        return 0
    fi

    local pull_cmd=(podman pull)
    local run_cmd=(podman run -d)

    if [ -n "${PLATFORM:-}" ]; then
        pull_cmd+=(--platform="${PLATFORM}")
        run_cmd+=(--platform="${PLATFORM}")
        logInfo "Pulling image (${PLATFORM}): ${IMAGE}"
    else
        logInfo "Pulling image: ${IMAGE}"
    fi

    if ! "${pull_cmd[@]}" "${IMAGE}"; then
        logError "Failed to pull image."
        return 1
    fi

    logInfo "Launching new ADB-Free container..."
    countDown "Starting container" 15

    run_cmd+=(
        "${CONTAINER_PORT_ARGS[@]}"
        -e "WORKLOAD_TYPE=${WORKLOAD_TYPE}"
        -e "WALLET_PASSWORD=${WALLET_PASSWORD}"
        -e "ADMIN_PASSWORD=${ADMIN_PASSWORD}"
        --cap-add SYS_ADMIN
        --device /dev/fuse
        --name "${CONTAINER_NAME}"
        --network "${DATALAKE_NETWORK}"
        --add-host cloudfs.home.com:192.168.1.191
        "${IMAGE}"
    )

    if ! "${run_cmd[@]}"; then
        logError "Container start failed."
        return 1
    fi

    logInfo "Container started."
    countDown "Waiting for Oracle services to initialize" 10
    autoConfigureDataLake
    listPorts
    #openORDS
}

stopContainer() {
    requirePodman
    if containerRunning; then
        logInfo "Stopping container..."
        podman stop "${CONTAINER_NAME}"
    else
        logError "Container is not running."
    fi
}

removeContainer() {
    requirePodman
    if containerExists; then
        logWarn "Removing container (ALL data stored inside will be lost)..."
        podman rm -f "${CONTAINER_NAME}"
    else
        logError "Container does not exist."
    fi
}


manageMongoTLS() {
    requirePodman

    if ! containerRunning; then
        logError "Oracle container is not running."
        return 1
    fi

    local action="${1:-menu}"

    case "${action}" in
        status|check|info)
            logInfo "Checking ORDS MongoDB API TLS status..."
            podman exec --user root "${CONTAINER_NAME}" \
                ords config info mongo.tls
            ;;

        enable|on|true)
            logInfo "Enabling ORDS TLS for the MongoDB API endpoint..."
            if podman exec --user root "${CONTAINER_NAME}" \
                ords config set mongo.tls true; then
                logInfo "ORDS MongoDB API TLS is configured as enabled."
                podman exec --user root "${CONTAINER_NAME}" \
                    ords config info mongo.tls
            else
                logError "Failed to enable ORDS MongoDB API TLS."
                return 1
            fi
            ;;

        disable|off|false)
            logInfo "Disabling ORDS TLS for the MongoDB API endpoint..."
            if podman exec --user root "${CONTAINER_NAME}" \
                ords config set mongo.tls false; then
                logInfo "ORDS MongoDB API TLS is configured as disabled."
                podman exec --user root "${CONTAINER_NAME}" \
                    ords config info mongo.tls
            else
                logError "Failed to disable ORDS MongoDB API TLS."
                return 1
            fi
            ;;

        menu)
            echo
            echo -e "${GREEN}ORDS MongoDB API TLS${NC}"
            echo -e "${GREEN}--------------------${NC}"
            echo "1. Check TLS status"
            echo "2. Enable TLS"
            echo "3. Disable TLS"
            echo "4. Return to main menu"
            echo

            local tls_opt
            read -r -p "Choose an option: " tls_opt

            case "${tls_opt}" in
                1) manageMongoTLS status ;;
                2) manageMongoTLS enable ;;
                3) manageMongoTLS disable ;;
                4) return 0 ;;
                *)
                    logError "Invalid TLS option."
                    return 1
                    ;;
            esac
            ;;

        *)
            logError "Invalid MongoDB TLS action: ${action}"
            echo "Usage: $0 mongoTLS [status|enable|disable]"
            return 2
            ;;
    esac
}



################################################################################
# Menu System
################################################################################

# Bypass menu
case "${1:-}" in
    "start")
        startContainer
        exit 0
        ;;
    "stop")
        stopContainer
        exit 0
        ;;
    "remove")
        removeContainer
        exit 0
        ;;
    "createUser")
        createUser
        exit 0
        ;;
    "showAdminInfo")
        showAdminInfo
        exit 0
        ;;
    "sqladmin")
        sqlPlusAdmin
        exit 0
        ;;
    "sqluser")
        sqlPlusUser
        exit 0
        ;;
    "ports")
        listPorts
        exit 0
        ;;
    "adbcli")
        adbCLI
        exit 0
        ;;
    "ords")
        openORDS
        exit 0
        ;;
    "restart")
        restartContainer
        exit 0
        ;;
    "root")
        rootAccess
        exit 0
        ;;
    "oracle")
        oracleAccess
        exit 0
        ;;
    "logs")
        showLogs
        exit 0
        ;;
    "taillogs")
        tailLogs
        exit 0
        ;;
    "copyIn")
        copyIn
        exit 0
        ;;
    "mongoTLS"|"mongotls"|"mongo-tls")
        manageMongoTLS "${2:-status}"
        exit $?
        ;;
    "datalake"|"datalakeConnect")
        configureDataLakeConnection
        exit $?
        ;;
    "datalakeInfo")
        showDataLakeInfo
        exit 0
        ;;
    "datalakeTest")
        testDataLakeConnection
        exit $?
        ;;
    "datalakeCA")
        syncDataLakeCA
        exit $?
        ;;
    "datalakeDB")
        configureDataLakeDatabase
        exit $?
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [start|stop|restart|remove|createUser|showAdminInfo|sqladmin|sqluser|ports|adbcli|ords|root|oracle|logs|taillogs|copyIn|mongoTLS|datalake|datalakeDB]"
        echo
        echo "MongoDB API TLS:"
        echo "  $0 mongoTLS status"
        echo "  $0 mongoTLS enable"
        echo "  $0 mongoTLS disable"
        echo
        echo "Spark / MinIO data lake:"
        echo "  $0 datalake        # join network, sync CA, test HTTPS"
        echo "  $0 datalakeInfo    # show shared network and S3 details"
        echo "  $0 datalakeTest    # test DNS and trusted HTTPS from Oracle"
        echo "  $0 datalakeCA      # refresh MinIO CA from minio-s3-tls"
        echo "  $0 datalakeDB      # configure DBMS_CLOUD credential/ACL and list objects"
        echo
        echo "Environment overrides:"
        echo "  ORACLE_DATALAKE_NETWORK, ORACLE_DATALAKE_TLS_CONTAINER"
        echo "  ORACLE_DATALAKE_S3_ROOT_HOST, ORACLE_DATALAKE_S3_HOST"
        echo "  ORACLE_DATALAKE_BUCKET, ORACLE_DATALAKE_S3_ACCESS_KEY"
        echo "  ORACLE_DATALAKE_S3_SECRET_KEY, ORACLE_DATALAKE_CREDENTIAL"
        exit 0
        ;;
esac

printMenuRow() {
    local left_color="$1"
    local left_text="$2"
    local right_color="$3"
    local right_text="$4"

    # Keep ANSI color sequences outside the padded text so printf alignment
    # is based only on the visible menu text.
    printf "%b%-38s%b  %b%s%b\n" \
        "${left_color}" "${left_text}" "${NC}" \
        "${right_color}" "${right_text}" "${NC}"
}

printMenuSectionHeader() {
    local left_title="$1"
    local right_title="$2"

    printf "%b%-38s%b  %b%s%b\n" \
        "${GREEN}" "${left_title}" "${NC}" \
        "${GREEN}" "${right_title}" "${NC}"
    printf "%-38s  %s\n" \
        "--------------------" "------------------------"
}

showMainMenu() {
    local term_width
    term_width="$(tput cols 2>/dev/null || printf '80')"

    echo
    echo -e "${GREEN}Oracle ADB-Free Podman Manager${NC}"
    echo -e "${GREEN}--------------------------------------------------------------------------------${NC}"

    if [ "${term_width}" -ge 80 ]; then
        # Group related operations side-by-side for normal terminal widths.
        printMenuSectionHeader "Container Management" "Oracle AI ADB Management"
        printMenuRow "${GREEN}"  "1. Start ADB-Free"       "${GREEN}" "9. Show Admin Info"
        printMenuRow "${YELLOW}" "2. Stop Container"      "${GREEN}" "10. Create Database User"
        printMenuRow "${GREEN}"  "3. Restart Container"   "${GREEN}" "11. SQL Admin Session"
        printMenuRow "${GREEN}"  "4. Show Ports"          "${GREEN}" "12. SQL User Session"
        printMenuRow "${GREEN}"  "5. Show Logs"           "${GREEN}" "13. Open ORDS"
        printMenuRow "${GREEN}"  "6. Tail Logs"           "${GREEN}" "14. ORDS MongoDB API TLS"
        printMenuRow "${GREEN}"  "7. Copy in File"        "${GREEN}" ""
        printMenuRow "${YELLOW}" "8. Quit"                "${GREEN}" ""
        echo

        printMenuSectionHeader "Shell Access" "Data Lake / MinIO"
        printMenuRow "${GREEN}" "15. Oracle Shell"        "${GREEN}" "18. Show Data Lake Info"
        printMenuRow "${GREEN}" "16. Root Shell"          "${GREEN}" "19. Connect / Refresh Data Lake"
        printMenuRow "${GREEN}" "17. ADB-CLI Shell"       "${GREEN}" "20. Test Data Lake Connectivity"
        printMenuRow "${GREEN}" ""                        "${GREEN}" "21. Configure DBMS_CLOUD"
        echo
        printMenuSectionHeader "Destroy Area" ""
        printMenuRow "${RED}" "22. Remove Container (DESTROYS ALL DATA)" "${GREEN}" ""
    else
        # Compact single-column fallback for narrow terminals.
        echo -e "${GREEN}Container Management${NC}"
        echo "--------------------"
        echo -e "${GREEN}1. Start ADB-Free${NC}"
        echo -e "${YELLOW}2. Stop Container${NC}"
        echo -e "${GREEN}3. Restart Container${NC}"
        echo -e "${GREEN}4. Show Ports${NC}"
        echo -e "${GREEN}5. Show Logs${NC}"
        echo -e "${GREEN}6. Tail Logs${NC}"
        echo -e "${GREEN}7. Copy in File${NC}"
        echo -e "${YELLOW}8. Quit${NC}"
        echo

        echo -e "${GREEN}Oracle AI ADB Management${NC}"
        echo "------------------------"
        echo -e "${GREEN}9. Show Admin Info${NC}"
        echo -e "${GREEN}10. Create Database User${NC}"
        echo -e "${GREEN}11. SQL Admin Session${NC}"
        echo -e "${GREEN}12. SQL User Session${NC}"
        echo -e "${GREEN}13. Open ORDS${NC}"
        echo -e "${GREEN}14. ORDS MongoDB API TLS${NC}"
        echo

        echo -e "${GREEN}Shell Access${NC}"
        echo "------------"
        echo -e "${GREEN}15. Oracle Shell${NC}"
        echo -e "${GREEN}16. Root Shell${NC}"
        echo -e "${GREEN}17. ADB-CLI Shell${NC}"
        echo

        echo -e "${GREEN}Data Lake / MinIO${NC}"
        echo "-----------------"
        echo -e "${GREEN}18. Show Data Lake Info${NC}"
        echo -e "${GREEN}19. Connect / Refresh Data Lake${NC}"
        echo -e "${GREEN}20. Test Data Lake Connectivity${NC}"
        echo -e "${GREEN}21. Configure DBMS_CLOUD${NC}"
        echo

        echo -e "${GREEN}Destroy Area${NC}"
        echo "------------"
        echo -e "${RED}22. Remove Container (DESTROYS ALL DATA)${NC}"
    fi

    echo
}

while true; do
    clear
    showMainMenu

    read -r -p "Choose an option: " opt
    case "$opt" in
        1) startContainer ;;
        2) stopContainer ;;
        3) restartContainer ;;
        4) listPorts ;;
        5) showLogs ;;
        6) tailLogs ;;
        7) copyIn ;;
        8) exit 0 ;;
        9) showAdminInfo ;;
        10) createUser ;;
        11) sqlPlusAdmin ;;
        12) sqlPlusUser ;;
        13) openORDS ;;
        14) manageMongoTLS ;;
        15) oracleAccess ;;
        16) rootAccess ;;
        17) adbCLI ;;
        18) showDataLakeInfo ;;
        19) configureDataLakeConnection ;;
        20) testDataLakeConnection ;;
        21) configureDataLakeDatabase ;;
        22) removeContainer ;;
        *) echo "Invalid choice"; sleep 1 ;;
    esac

    echo
    read -r -p "Press enter to continue..." dummy
done
#!/usr/bin/env bash

################################################################################
# Spark + Iceberg Quickstart – Container Manager
#
# FILE:
#   sparkIcebergManager.sh
#
# USAGE:
#   ./sparkIcebergManager.sh [command]
#
# DESCRIPTION:
#   Wrapper script with both an interactive menu and command-line bypass options
#   for managing the Databricks Spark + Iceberg Quickstart Compose environment.
#
# FEATURES:
#   - Detect and use Docker or Podman automatically
#   - Clone the upstream Databricks Spark + Iceberg Quickstart repository
#   - Start, stop, restart, update, build, and remove the environment
#   - Show container status, ports, logs, credentials, and Compose configuration
#   - Open Jupyter, Spark UI, MinIO Console, and the Iceberg REST endpoint
#   - Launch Bash, PySpark, Spark SQL, Scala Spark, and MinIO shells
#   - Check container and HTTP endpoint health
#   - Interactive menu-driven execution
#   - Direct command-line bypass support
#   - Compact two-column menu organized by logical function
#   - Persist MinIO object data in a container-engine managed named volume
#   - Preserve the MinIO warehouse bucket across environment restarts
#   - Create a shared container network for Oracle Autonomous AI Database access
#   - Expose MinIO to Oracle through an internal HTTPS/S3 endpoint on port 443
#   - Generate and manage a local CA and TLS certificate for the S3 endpoint
#   - Test the Oracle-facing S3-compatible endpoint from the shared network
#   - Attach an existing Oracle ADB container to the shared data-lake network
#   - Install the generated local CA in an attached Oracle container OS truststore
#   - Default Oracle integration to the myadb container created by orclADBPodman.sh
#   - Expose the local CA through the TLS proxy for cross-script trust synchronization
#   - Auto-connect a running Oracle ADB container when the Spark stack starts
#
# REQUIREMENTS:
#   - Bash 4 or later
#   - Git installed and available in PATH
#   - OpenSSL installed and available in PATH
#   - Docker with Docker Compose v2, or Podman with a Compose provider
#   - curl for host HTTP endpoint health checks
#   - Internet connectivity for the initial clone and container image pulls
#   - Free local ports 8080, 8181, 8888, 9000, 9001, 10000, and 10001
#
# NOTES:
#   - Intended for local Spark, Apache Iceberg, MinIO, and Oracle ADB learning
#   - This environment is not a local installation of the Databricks platform
#   - Jupyter authentication is disabled by the upstream quickstart image
#   - MinIO uses development credentials; do not expose it to untrusted networks
#   - MinIO remains the authoritative object store; no NFS layer is used
#   - Spark/Iceberg access MinIO directly over HTTP on their private Compose network
#   - Oracle containers access MinIO through an HTTPS reverse proxy on port 443
#   - The Oracle-facing DNS name is available only on the shared container network
#   - Review port mappings, credentials, certificates, and network ACLs before use
#
# SOURCE:
#   https://github.com/databricks/docker-spark-iceberg
#
# AUTHOR:
#   Matt DeMarco
#
# CREATED:
#   08.20.2026
#
# VERSION:
#   1.2.0
################################################################################

# Copyright (c) 2026 Matt DeMarco.

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

SCRIPT_VERSION="1.2.0"
REPOSITORY_URL="${SPARK_ICEBERG_REPOSITORY_URL:-https://github.com/databricks/docker-spark-iceberg.git}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
    DEFAULT_PROJECT_DIR="${SCRIPT_DIR}"
else
    DEFAULT_PROJECT_DIR="${SCRIPT_DIR}/docker-spark-iceberg"
fi

PROJECT_DIR="${SPARK_ICEBERG_HOME:-${DEFAULT_PROJECT_DIR}}"
COMPOSE_FILE="${PROJECT_DIR}/docker-compose.yml"
COMPOSE_OVERRIDE_FILE="${PROJECT_DIR}/docker-compose.oracle-datalake.yml"
SPARK_SERVICE="spark-iceberg"
MINIO_SERVICE="minio"
MINIO_TLS_SERVICE="minio-s3-tls"

INTEGRATION_DIR="${PROJECT_DIR}/.oracle-datalake"
TLS_DIR="${INTEGRATION_DIR}/tls"
NGINX_CONFIG_FILE="${INTEGRATION_DIR}/nginx.conf"
CA_CERT_FILE="${TLS_DIR}/ca.crt"
CA_KEY_FILE="${TLS_DIR}/ca.key"
SERVER_CERT_FILE="${TLS_DIR}/server.crt"
SERVER_KEY_FILE="${TLS_DIR}/server.key"
TLS_METADATA_FILE="${TLS_DIR}/metadata"

DATALAKE_NETWORK="${SPARK_ICEBERG_NETWORK:-oracle-datalake}"
MINIO_VOLUME_NAME="${SPARK_ICEBERG_MINIO_VOLUME:-spark-iceberg-minio-data}"
MINIO_TLS_IMAGE="${SPARK_ICEBERG_TLS_PROXY_IMAGE:-nginx:alpine}"
MINIO_MC_IMAGE="${SPARK_ICEBERG_MC_IMAGE:-minio/mc:latest}"
ORACLE_CONTAINER_DEFAULT="${ORACLE_ADB_CONTAINER:-myadb}"

# These match the upstream Databricks Spark + Iceberg quickstart defaults.
MINIO_ACCESS_KEY="admin"
MINIO_SECRET_KEY="password"
MINIO_BUCKET="warehouse"
MINIO_INTERNAL_HOST="minio"
MINIO_ORACLE_HOST="warehouse.minio"
MINIO_ORACLE_ROOT_HOST="minio"
MINIO_TLS_CA_CONTAINER_PATH="/etc/nginx/tls/ca.crt"

JUPYTER_URL="http://localhost:8888"
SPARK_UI_URL="http://localhost:8080"
ICEBERG_REST_URL="http://localhost:8181"
MINIO_API_URL="http://localhost:9000"
MINIO_CONSOLE_URL="http://localhost:9001"
MINIO_ORACLE_HTTPS_URL="https://${MINIO_ORACLE_HOST}"
MINIO_ORACLE_S3_PREFIX="s3://${MINIO_ORACLE_HOST}/"

RUNTIME=""
COMPOSE_CMD=()

COLOR_BLUE='\033[0;34m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_BOLD='\033[1m'
COLOR_RESET='\033[0m'

info() {
    printf '%b[INFO]%b %s\n' "${COLOR_BLUE}" "${COLOR_RESET}" "$*"
}

success() {
    printf '%b[OK]%b %s\n' "${COLOR_GREEN}" "${COLOR_RESET}" "$*"
}

warn() {
    printf '%b[WARN]%b %s\n' "${COLOR_YELLOW}" "${COLOR_RESET}" "$*" >&2
}

error() {
    printf '%b[ERROR]%b %s\n' "${COLOR_RED}" "${COLOR_RESET}" "$*" >&2
}

pause() {
    if [[ -t 0 ]]; then
        read -r -p "Press Enter to continue..." _unused
    fi
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        error "Required command not found: $1"
        return 1
    fi
}

detect_runtime() {
    local preferred="${CONTAINER_ENGINE:-}"

    if [[ -n "${preferred}" ]]; then
        if ! command -v "${preferred}" >/dev/null 2>&1; then
            error "CONTAINER_ENGINE is set to '${preferred}', but that command is unavailable."
            return 1
        fi
        RUNTIME="${preferred}"
    elif command -v podman >/dev/null 2>&1; then
        RUNTIME="podman"
    elif command -v docker >/dev/null 2>&1; then
        RUNTIME="docker"
    else
        error "Neither Podman nor Docker was found in PATH."
        return 1
    fi

    if "${RUNTIME}" compose version >/dev/null 2>&1; then
        COMPOSE_CMD=("${RUNTIME}" compose)
    elif [[ "${RUNTIME}" == "podman" ]] && command -v podman-compose >/dev/null 2>&1; then
        COMPOSE_CMD=(podman-compose)
    elif [[ "${RUNTIME}" == "docker" ]] && command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD=(docker-compose)
    else
        error "A Compose provider for ${RUNTIME} was not found."
        return 1
    fi
}

runtime_ready() {
    if ! "${RUNTIME}" info >/dev/null 2>&1; then
        error "${RUNTIME} is installed, but its service or virtual machine is not running."
        if [[ "${RUNTIME}" == "podman" ]]; then
            warn "On macOS or Windows, try: podman machine start"
        else
            warn "Start Docker Desktop or the Docker daemon and try again."
        fi
        return 1
    fi
}

ensure_project() {
    if [[ -f "${COMPOSE_FILE}" ]]; then
        return 0
    fi

    require_command git || return 1

    if [[ -e "${PROJECT_DIR}" ]]; then
        error "Project directory exists but docker-compose.yml is missing: ${PROJECT_DIR}"
        return 1
    fi

    info "Cloning the Spark + Iceberg Quickstart into ${PROJECT_DIR}"
    git clone "${REPOSITORY_URL}" "${PROJECT_DIR}" || return 1

    if [[ ! -f "${COMPOSE_FILE}" ]]; then
        error "Clone completed, but docker-compose.yml was not found."
        return 1
    fi
}

ensure_tls_assets() {
    local expected_metadata
    expected_metadata="oracle_host=${MINIO_ORACLE_HOST};root_host=${MINIO_ORACLE_ROOT_HOST}"

    if [[ -f "${CA_CERT_FILE}" && -f "${CA_KEY_FILE}" && \
          -f "${SERVER_CERT_FILE}" && -f "${SERVER_KEY_FILE}" && \
          -f "${TLS_METADATA_FILE}" ]] && \
       [[ "$(cat "${TLS_METADATA_FILE}" 2>/dev/null)" == "${expected_metadata}" ]]; then
        return 0
    fi

    require_command openssl || return 1
    mkdir -p "${TLS_DIR}" || return 1

    if [[ -e "${CA_CERT_FILE}" || -e "${CA_KEY_FILE}" || \
          -e "${SERVER_CERT_FILE}" || -e "${SERVER_KEY_FILE}" ]]; then
        warn "TLS identity changed or is incomplete; regenerating the local data-lake CA and server certificate."
        warn "Any Oracle container that trusted the previous CA must be updated again."
        rm -f "${CA_CERT_FILE}" "${CA_KEY_FILE}" \
              "${SERVER_CERT_FILE}" "${SERVER_KEY_FILE}" \
              "${TLS_DIR}/server.csr" "${TLS_DIR}/server.ext"
    fi

    info "Generating local CA for the Oracle-facing MinIO HTTPS endpoint."
    openssl req \
        -x509 \
        -newkey rsa:2048 \
        -sha256 \
        -days 3650 \
        -nodes \
        -keyout "${CA_KEY_FILE}" \
        -out "${CA_CERT_FILE}" \
        -subj "/CN=Oracle Data Lake Local CA" \
        >/dev/null 2>&1 || return 1

    info "Generating TLS certificate for ${MINIO_ORACLE_HOST}."
    openssl req \
        -new \
        -newkey rsa:2048 \
        -sha256 \
        -nodes \
        -keyout "${SERVER_KEY_FILE}" \
        -out "${TLS_DIR}/server.csr" \
        -subj "/CN=${MINIO_ORACLE_HOST}" \
        >/dev/null 2>&1 || return 1

    cat > "${TLS_DIR}/server.ext" <<EOF
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:${MINIO_ORACLE_HOST},DNS:${MINIO_ORACLE_ROOT_HOST},DNS:${MINIO_TLS_SERVICE},DNS:localhost
EOF

    openssl x509 \
        -req \
        -in "${TLS_DIR}/server.csr" \
        -CA "${CA_CERT_FILE}" \
        -CAkey "${CA_KEY_FILE}" \
        -CAcreateserial \
        -out "${SERVER_CERT_FILE}" \
        -days 825 \
        -sha256 \
        -extfile "${TLS_DIR}/server.ext" \
        >/dev/null 2>&1 || return 1

    rm -f "${TLS_DIR}/server.csr" "${TLS_DIR}/server.ext" "${TLS_DIR}/ca.srl"
    chmod 600 "${CA_KEY_FILE}" "${SERVER_KEY_FILE}"
    chmod 644 "${CA_CERT_FILE}" "${SERVER_CERT_FILE}"
    printf '%s\n' "${expected_metadata}" > "${TLS_METADATA_FILE}"

    success "Local TLS assets generated under ${TLS_DIR}."
}

write_nginx_config() {
    mkdir -p "${INTEGRATION_DIR}" || return 1

    cat > "${NGINX_CONFIG_FILE}" <<EOF
worker_processes auto;

events {
    worker_connections 1024;
}

http {
    server_tokens off;
    client_max_body_size 0;

    server {
        listen 443 ssl;
        server_name ${MINIO_ORACLE_ROOT_HOST} ${MINIO_ORACLE_HOST};

        ssl_certificate     /etc/nginx/tls/server.crt;
        ssl_certificate_key /etc/nginx/tls/server.key;
        ssl_protocols       TLSv1.2 TLSv1.3;

        location / {
            proxy_http_version 1.1;
            proxy_request_buffering off;
            proxy_buffering off;
            proxy_connect_timeout 300s;
            proxy_send_timeout 300s;
            proxy_read_timeout 300s;

            # Preserve the original S3 host and request path. This is required
            # for AWS Signature Version 4 validation and MinIO virtual-hosted
            # bucket addressing (for example: warehouse.minio).
            proxy_set_header Host \$http_host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Forwarded-Host \$http_host;
            proxy_set_header X-Forwarded-Port 443;
            proxy_set_header Connection "";

            proxy_pass http://${MINIO_INTERNAL_HOST}:9000;
            proxy_redirect off;
        }
    }
}
EOF
}

write_compose_override() {
    mkdir -p "${PROJECT_DIR}" || return 1

    cat > "${COMPOSE_OVERRIDE_FILE}" <<EOF
# Generated by sparkIcebergManager.sh ${SCRIPT_VERSION}
# Do not edit manually; the manager regenerates this file as needed.

services:
  minio:
    volumes:
      - minio-data:/data

  mc:
    entrypoint: >
      /bin/sh -c "
      until (/usr/bin/mc alias set minio http://minio:9000 ${MINIO_ACCESS_KEY} ${MINIO_SECRET_KEY}) do echo '...waiting for MinIO...' && sleep 1; done;
      /usr/bin/mc mb --ignore-existing minio/${MINIO_BUCKET};
      /usr/bin/mc anonymous set public minio/${MINIO_BUCKET};
      tail -f /dev/null
      "

  ${MINIO_TLS_SERVICE}:
    image: ${MINIO_TLS_IMAGE}
    container_name: ${MINIO_TLS_SERVICE}
    depends_on:
      - minio
    volumes:
      - ./.oracle-datalake/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./.oracle-datalake/tls/server.crt:/etc/nginx/tls/server.crt:ro
      - ./.oracle-datalake/tls/server.key:/etc/nginx/tls/server.key:ro
      - ./.oracle-datalake/tls/ca.crt:${MINIO_TLS_CA_CONTAINER_PATH}:ro
    networks:
      iceberg_net:
      oracle-datalake:
        aliases:
          - ${MINIO_ORACLE_ROOT_HOST}
          - ${MINIO_ORACLE_HOST}

networks:
  oracle-datalake:
    external: true
    name: ${DATALAKE_NETWORK}

volumes:
  minio-data:
    name: ${MINIO_VOLUME_NAME}
EOF
}

ensure_integration_assets() {
    ensure_tls_assets || return 1
    write_nginx_config || return 1
    write_compose_override || return 1
}

ensure_shared_network() {
    runtime_ready || return 1

    if "${RUNTIME}" network inspect "${DATALAKE_NETWORK}" >/dev/null 2>&1; then
        return 0
    fi

    info "Creating shared container network: ${DATALAKE_NETWORK}"
    "${RUNTIME}" network create "${DATALAKE_NETWORK}" >/dev/null || return 1
    success "Shared container network created: ${DATALAKE_NETWORK}"
}

compose() {
    ensure_project || return 1
    ensure_integration_assets || return 1
    (
        cd "${PROJECT_DIR}" || exit 1
        "${COMPOSE_CMD[@]}" \
            -f "${COMPOSE_FILE}" \
            -f "${COMPOSE_OVERRIDE_FILE}" \
            "$@"
    )
}

stack_exists() {
    compose ps -q 2>/dev/null | grep -q .
}

service_running() {
    local service="${1:-${SPARK_SERVICE}}"
    local container_id

    container_id="$(compose ps -q "${service}" 2>/dev/null)"
    [[ -n "${container_id}" ]] || return 1
    [[ "$("${RUNTIME}" inspect -f '{{.State.Running}}' "${container_id}" 2>/dev/null)" == "true" ]]
}

install_project() {
    ensure_project || return 1
    ensure_integration_assets || return 1
    success "Project is available at ${PROJECT_DIR}"
    success "Oracle data-lake integration assets are configured."
}

auto_connect_oracle_container() {
    local container_name="${ORACLE_CONTAINER_DEFAULT}"

    [[ -n "${container_name}" ]] || return 0

    if ! "${RUNTIME}" inspect "${container_name}" >/dev/null 2>&1; then
        if [[ "${RUNTIME}" != "podman" ]] && command -v podman >/dev/null 2>&1 && \
           podman inspect "${container_name}" >/dev/null 2>&1; then
            warn "Oracle container ${container_name} exists in Podman, but Spark is using ${RUNTIME}."
            warn "The two scripts must use the same container runtime. Re-run with CONTAINER_ENGINE=podman."
        fi
        return 0
    fi

    if [[ "$("${RUNTIME}" inspect -f '{{.State.Running}}' "${container_name}" 2>/dev/null)" != "true" ]]; then
        warn "Oracle container ${container_name} exists but is not running; skipping automatic data-lake attachment."
        return 0
    fi

    info "Detected running Oracle ADB container ${container_name}; validating shared data-lake integration."
    if ! connect_oracle_container "${container_name}"; then
        warn "Spark + Iceberg started, but automatic Oracle data-lake integration was not completed."
        warn "Retry with: $(basename "$0") connectoracle ${container_name}"
    fi

    return 0
}

start_stack() {
    runtime_ready || return 1
    ensure_project || return 1
    ensure_integration_assets || return 1
    ensure_shared_network || return 1

    info "Starting the Spark + Iceberg environment with ${COMPOSE_CMD[*]}"
    compose up -d || return 1
    success "Spark + Iceberg environment started."
    auto_connect_oracle_container
    show_endpoints
}

stop_stack() {
    runtime_ready || return 1
    if ! stack_exists; then
        warn "No Compose containers were found for this project."
        return 0
    fi
    compose stop && success "Spark + Iceberg services stopped."
}

restart_stack() {
    runtime_ready || return 1
    ensure_shared_network || return 1
    if stack_exists; then
        compose restart && success "Spark + Iceberg services restarted."
    else
        start_stack
    fi
}

remove_stack() {
    runtime_ready || return 1
    if ! stack_exists; then
        warn "No Compose containers were found for this project."
        return 0
    fi

    printf '%bThis removes the Compose containers and project-private network.%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
    printf 'The MinIO named volume %s will be preserved.\n' "${MINIO_VOLUME_NAME}"
    printf 'The shared external network %s will be preserved.\n' "${DATALAKE_NETWORK}"
    read -r -p "Type REMOVE to continue: " confirmation
    if [[ "${confirmation}" != "REMOVE" ]]; then
        warn "Remove cancelled."
        return 0
    fi

    compose down --remove-orphans && success "Compose containers and project-private network removed."
}

update_project() {
    runtime_ready || return 1
    ensure_project || return 1

    if [[ -d "${PROJECT_DIR}/.git" ]]; then
        info "Updating the upstream repository with a fast-forward-only pull."
        git -C "${PROJECT_DIR}" pull --ff-only || return 1
    else
        warn "${PROJECT_DIR} is not a Git checkout; skipping source update."
    fi

    ensure_integration_assets || return 1

    info "Pulling current container images."
    compose pull || return 1
    success "Source and container images updated."
}

build_images() {
    runtime_ready || return 1
    info "Building the Spark image from the repository Dockerfile."
    compose build || return 1
    success "Build completed."
}

show_status() {
    runtime_ready || return 1
    ensure_project || return 1
    compose ps
}

show_ports() {
    printf '%-24s %-30s %s\n' "SERVICE" "ENDPOINT" "PURPOSE"
    printf '%-24s %-30s %s\n' "----------------------" "----------------------------" "--------------------------------"
    printf '%-24s %-30s %s\n' "Jupyter Notebook" "${JUPYTER_URL}" "PySpark and Scala notebooks"
    printf '%-24s %-30s %s\n' "Spark UI" "${SPARK_UI_URL}" "Spark master and job visibility"
    printf '%-24s %-30s %s\n' "Iceberg REST" "${ICEBERG_REST_URL}" "Iceberg REST catalog"
    printf '%-24s %-30s %s\n' "MinIO API (host)" "${MINIO_API_URL}" "S3-compatible object storage"
    printf '%-24s %-30s %s\n' "MinIO Console" "${MINIO_CONSOLE_URL}" "Object-storage administration"
    printf '%-24s %-30s %s\n' "Oracle S3 (container)" "${MINIO_ORACLE_HTTPS_URL}:443" "HTTPS/S3 on ${DATALAKE_NETWORK}"
    printf '%-24s %-30s %s\n' "Spark Thrift" "localhost:10000" "Spark SQL Thrift/JDBC"
    printf '%-24s %-30s %s\n' "Spark Thrift HTTP" "localhost:10001" "Spark Thrift HTTP transport"
}

show_credentials() {
    cat <<EOF
Jupyter Notebook
  Username: none
  Password: none
  Token:    disabled by the upstream image

MinIO Console and S3-compatible API
  Access key: ${MINIO_ACCESS_KEY}
  Secret key: ${MINIO_SECRET_KEY}
  Bucket:     ${MINIO_BUCKET}

Spark / Iceberg MinIO endpoint
  Endpoint:   http://${MINIO_INTERNAL_HOST}:9000
  URI:        s3://${MINIO_BUCKET}/

Oracle-container MinIO endpoint
  Network:    ${DATALAKE_NETWORK}
  HTTPS:      ${MINIO_ORACLE_HTTPS_URL}:443
  DBMS_CLOUD: ${MINIO_ORACLE_S3_PREFIX}<object-name>
  CA cert:    ${CA_CERT_FILE}

Spark UI and Iceberg REST catalog
  Authentication: none

WARNING: These development services and credentials are intended only for an isolated lab.
EOF
}

show_s3_info() {
    ensure_project || return 1
    ensure_integration_assets || return 1

    cat <<EOF
MinIO S3-Compatible Object Storage

Authoritative storage
  Bucket:              ${MINIO_BUCKET}
  Named volume:        ${MINIO_VOLUME_NAME}
  Persistence:         Preserved by 'remove' (Compose down does not delete the volume)

Spark / Iceberg access
  Network:             iceberg_net (Compose-private)
  Endpoint:            http://${MINIO_INTERNAL_HOST}:9000
  Warehouse URI:       s3://${MINIO_BUCKET}/

Oracle ADB container access
  Shared network:      ${DATALAKE_NETWORK}
  HTTPS endpoint:      ${MINIO_ORACLE_HTTPS_URL}:443
  S3-compatible URI:   ${MINIO_ORACLE_S3_PREFIX}<object-name>
  Root S3 endpoint:    https://${MINIO_ORACLE_ROOT_HOST}:443

Credentials
  Access key:          ${MINIO_ACCESS_KEY}
  Secret key:          ${MINIO_SECRET_KEY}

TLS
  Local CA certificate: ${CA_CERT_FILE}
  Server certificate:   ${SERVER_CERT_FILE}

Oracle container attachment
  Default container:     ${ORACLE_CONTAINER_DEFAULT}
  $(basename "$0") connectoracle [oracle-container-name]
  The matching orclADBPodman.sh can also join ${DATALAKE_NETWORK} directly
  and read the CA from the running ${MINIO_TLS_SERVICE} container.

Example DBMS_CLOUD object URI
  ${MINIO_ORACLE_S3_PREFIX}oracle-export/customers.parquet
EOF
}

show_endpoints() {
    printf '\n'
    show_ports
    printf '\nMinIO credentials: %s / %s\n' "${MINIO_ACCESS_KEY}" "${MINIO_SECRET_KEY}"
    printf 'MinIO bucket:      %s\n' "${MINIO_BUCKET}"
    printf 'Shared network:    %s\n' "${DATALAKE_NETWORK}"
    printf 'Oracle S3 URI:     %s<object-name>\n' "${MINIO_ORACLE_S3_PREFIX}"
    printf 'Jupyter authentication: disabled\n'
}

show_logs() {
    runtime_ready || return 1
    compose logs --tail=200
}

tail_logs() {
    runtime_ready || return 1
    compose logs -f --tail=100
}

show_config() {
    compose config
}

show_ca_info() {
    ensure_project || return 1
    ensure_integration_assets || return 1
    require_command openssl || return 1

    printf 'Local Oracle Data Lake CA\n'
    printf '  File: %s\n' "${CA_CERT_FILE}"
    openssl x509 \
        -in "${CA_CERT_FILE}" \
        -noout \
        -subject \
        -issuer \
        -dates \
        -fingerprint \
        -sha256
}

regenerate_tls() {
    ensure_project || return 1
    require_command openssl || return 1

    printf '%bRegenerating the data-lake CA invalidates the previous Oracle trust relationship.%b\n' \
        "${COLOR_YELLOW}" "${COLOR_RESET}"
    if [[ -t 0 ]]; then
        read -r -p "Type REGENERATE to continue: " confirmation
        if [[ "${confirmation}" != "REGENERATE" ]]; then
            warn "TLS regeneration cancelled."
            return 0
        fi
    fi

    rm -rf "${TLS_DIR}"
    ensure_integration_assets || return 1

    if runtime_ready >/dev/null 2>&1 && service_running "${MINIO_TLS_SERVICE}"; then
        compose restart "${MINIO_TLS_SERVICE}" || return 1
    fi

    success "TLS assets regenerated. Re-run 'connectoracle' for Oracle containers that trusted the old CA."
}

open_url() {
    local url="$1"

    if command -v open >/dev/null 2>&1; then
        open "${url}"
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "${url}" >/dev/null 2>&1 &
    elif command -v wslview >/dev/null 2>&1; then
        wslview "${url}"
    else
        info "Open this URL in your browser: ${url}"
        return 0
    fi
}

open_service() {
    local url="$1"
    if ! service_running "${SPARK_SERVICE}"; then
        warn "The Spark service does not appear to be running."
        warn "Start it with: $0 start"
        return 1
    fi
    open_url "${url}"
}

spark_exec() {
    runtime_ready || return 1
    if ! service_running "${SPARK_SERVICE}"; then
        error "The Spark service is not running. Start it first."
        return 1
    fi
    compose exec "${SPARK_SERVICE}" "$@"
}

spark_shell() {
    spark_exec bash
}

pyspark_shell() {
    spark_exec pyspark
}

spark_sql_shell() {
    spark_exec spark-sql
}

scala_shell() {
    spark_exec spark-shell
}

minio_shell() {
    runtime_ready || return 1
    if ! service_running "${MINIO_SERVICE}"; then
        error "The MinIO service is not running. Start the environment first."
        return 1
    fi
    compose exec "${MINIO_SERVICE}" sh
}

test_s3_access() {
    local quiet="${1:-false}"

    runtime_ready || return 1
    ensure_project || return 1
    ensure_integration_assets || return 1
    ensure_shared_network || return 1

    if ! service_running "${MINIO_TLS_SERVICE}"; then
        error "The Oracle-facing MinIO TLS service is not running."
        error "Start the environment first: $0 start"
        return 1
    fi

    if [[ "${quiet}" != "true" ]]; then
        info "Testing HTTPS, S3 authentication, and bucket access from ${DATALAKE_NETWORK}."
    fi

    if "${RUNTIME}" run \
        --rm \
        --network "${DATALAKE_NETWORK}" \
        -e "MC_HOST_datalake=https://${MINIO_ACCESS_KEY}:${MINIO_SECRET_KEY}@${MINIO_ORACLE_ROOT_HOST}" \
        "${MINIO_MC_IMAGE}" \
        --insecure ls "datalake/${MINIO_BUCKET}" \
        >/dev/null 2>&1; then
        if [[ "${quiet}" != "true" ]]; then
            success "Oracle-facing MinIO S3 endpoint is reachable and the ${MINIO_BUCKET} bucket is accessible."
        fi
        return 0
    fi

    if [[ "${quiet}" != "true" ]]; then
        error "S3 endpoint test failed."
        warn "Review: $0 logs"
        warn "Review: $0 s3info"
    fi
    return 1
}

container_on_shared_network() {
    local container_name="$1"
    local networks_json

    networks_json="$("${RUNTIME}" inspect -f '{{json .NetworkSettings.Networks}}' "${container_name}" 2>/dev/null)" || return 1
    [[ "${networks_json}" == *\"${DATALAKE_NETWORK}\"* ]]
}

install_ca_in_container() {
    local container_name="$1"
    local target_cert="/tmp/oracle-datalake-ca.crt"

    info "Copying local data-lake CA into ${container_name}."
    "${RUNTIME}" cp "${CA_CERT_FILE}" "${container_name}:${target_cert}" || return 1

    if "${RUNTIME}" exec --user 0 "${container_name}" sh -lc 'command -v update-ca-trust >/dev/null 2>&1'; then
        info "Installing CA into the Oracle container OS truststore."
        "${RUNTIME}" exec --user 0 "${container_name}" sh -lc \
            "cp '${target_cert}' /etc/pki/ca-trust/source/anchors/oracle-datalake-ca.crt && update-ca-trust" \
            || return 1
        success "Oracle container OS truststore updated."
    else
        warn "update-ca-trust is not available in ${container_name}; CA was copied to ${target_cert}."
        warn "Database-specific certificate trust may need to be configured manually."
    fi
}

connect_oracle_container() {
    local container_name="${1:-${ORACLE_CONTAINER_DEFAULT}}"

    runtime_ready || return 1
    ensure_project || return 1
    ensure_integration_assets || return 1
    ensure_shared_network || return 1

    if [[ -z "${container_name}" ]]; then
        error "Oracle container name is required."
        printf 'Usage: %s connectoracle <oracle-container-name>\n' "$(basename "$0")" >&2
        printf 'Or set ORACLE_ADB_CONTAINER=<oracle-container-name>.\n' >&2
        return 2
    fi

    if ! "${RUNTIME}" inspect "${container_name}" >/dev/null 2>&1; then
        if [[ "${RUNTIME}" != "podman" ]] && command -v podman >/dev/null 2>&1 && \
           podman inspect "${container_name}" >/dev/null 2>&1; then
            error "Container ${container_name} exists in Podman, but Spark is using ${RUNTIME}."
            error "Use the same runtime for both stacks, for example: CONTAINER_ENGINE=podman $0 connectoracle ${container_name}"
        else
            error "Container not found in ${RUNTIME}: ${container_name}"
        fi
        return 1
    fi

    if container_on_shared_network "${container_name}"; then
        success "${container_name} is already attached to ${DATALAKE_NETWORK}."
    else
        info "Attaching ${container_name} to ${DATALAKE_NETWORK}."
        "${RUNTIME}" network connect "${DATALAKE_NETWORK}" "${container_name}" || return 1
        success "${container_name} attached to ${DATALAKE_NETWORK}."
    fi

    install_ca_in_container "${container_name}" || return 1

    printf '\nOracle container data-lake connection\n'
    printf '  Container:       %s\n' "${container_name}"
    printf '  Network:         %s\n' "${DATALAKE_NETWORK}"
    printf '  HTTPS endpoint:  %s:443\n' "${MINIO_ORACLE_HTTPS_URL}"
    printf '  DBMS_CLOUD URI:  %s<object-name>\n' "${MINIO_ORACLE_S3_PREFIX}"
    printf '  Access key:      %s\n' "${MINIO_ACCESS_KEY}"
    printf '  Secret key:      %s\n' "${MINIO_SECRET_KEY}"
    printf '  CA in container: /etc/pki/ca-trust/source/anchors/oracle-datalake-ca.crt\n'

    if "${RUNTIME}" exec "${container_name}" sh -lc \
        "getent hosts '${MINIO_ORACLE_HOST}' >/dev/null 2>&1"; then
        success "Container DNS resolves ${MINIO_ORACLE_HOST}."
    else
        warn "Could not confirm DNS resolution for ${MINIO_ORACLE_HOST} inside ${container_name}."
    fi

    cat <<EOF

Next database-side steps:
  1. Create a DBMS_CLOUD credential using access key '${MINIO_ACCESS_KEY}'.
  2. Allow outbound access to '${MINIO_ORACLE_HOST}' with the applicable database ACL.
  3. Test DBMS_CLOUD against: ${MINIO_ORACLE_S3_PREFIX}<object-name>

Note: The script installs the CA in the container OS truststore. DBMS_CLOUD certificate
validation is performed by the database and can be version/configuration dependent. Use
an actual DBMS_CLOUD request as the final validation step.
EOF
}

prompt_connect_oracle() {
    local container_name="${ORACLE_CONTAINER_DEFAULT}"
    local entered=""

    if [[ -z "${container_name}" ]]; then
        read -r -p "Oracle ADB container name: " container_name
    else
        read -r -p "Oracle ADB container name [${container_name}]: " entered
        container_name="${entered:-${container_name}}"
    fi

    connect_oracle_container "${container_name}"
}

health_check() {
    local failed=0

    runtime_ready || return 1
    show_status
    printf '\nHost endpoint checks:\n'

    if ! command -v curl >/dev/null 2>&1; then
        warn "curl is unavailable; skipping host HTTP endpoint checks."
    else
        while IFS='|' read -r name url; do
            if curl --silent --show-error --location --max-time 5 --output /dev/null "${url}"; then
                printf '  %-22s %bAVAILABLE%b\n' "${name}" "${COLOR_GREEN}" "${COLOR_RESET}"
            else
                printf '  %-22s %bUNAVAILABLE%b\n' "${name}" "${COLOR_RED}" "${COLOR_RESET}"
                failed=1
            fi
        done <<EOF
Jupyter|${JUPYTER_URL}
Spark UI|${SPARK_UI_URL}
Iceberg REST|${ICEBERG_REST_URL}
MinIO API|${MINIO_API_URL}/minio/health/live
MinIO Console|${MINIO_CONSOLE_URL}
EOF
    fi

    printf '\nContainer-network S3 check:\n'
    if test_s3_access true; then
        printf '  %-22s %bAVAILABLE%b\n' "Oracle HTTPS/S3" "${COLOR_GREEN}" "${COLOR_RESET}"
    else
        printf '  %-22s %bUNAVAILABLE%b\n' "Oracle HTTPS/S3" "${COLOR_RED}" "${COLOR_RESET}"
        failed=1
    fi

    return "${failed}"
}

doctor() {
    printf 'Spark + Iceberg Manager diagnostics\n'
    printf '  Script version:      %s\n' "${SCRIPT_VERSION}"
    printf '  Project path:        %s\n' "${PROJECT_DIR}"
    printf '  Repository:          %s\n' "${REPOSITORY_URL}"
    printf '  Shared network:      %s\n' "${DATALAKE_NETWORK}"
    printf '  MinIO data volume:   %s\n' "${MINIO_VOLUME_NAME}"
    printf '  Oracle S3 hostname:  %s\n' "${MINIO_ORACLE_HOST}"
    printf '  Oracle container:    %s\n' "${ORACLE_CONTAINER_DEFAULT}"

    if detect_runtime; then
        printf '  Runtime:             %s\n' "${RUNTIME}"
        printf '  Compose:             %s\n' "${COMPOSE_CMD[*]}"
    else
        return 1
    fi

    if [[ -f "${COMPOSE_FILE}" ]]; then
        printf '  Compose file:        FOUND\n'
        if ensure_integration_assets; then
            printf '  Compose override:    READY\n'
            printf '  Local TLS assets:    READY\n'
        else
            printf '  Integration assets: ERROR\n'
            return 1
        fi
    else
        printf '  Compose file:        NOT INSTALLED\n'
    fi

    if runtime_ready; then
        if "${RUNTIME}" network inspect "${DATALAKE_NETWORK}" >/dev/null 2>&1; then
            printf '  Shared network:      EXISTS\n'
        else
            printf '  Shared network:      NOT CREATED (created automatically on start)\n'
        fi
    else
        return 1
    fi
}

print_menu_row() {
    printf '  %-40s %s\n' "$1" "$2"
}

show_menu() {
    clear 2>/dev/null || true
    printf '%b=================================================================%b\n' "${COLOR_BLUE}" "${COLOR_RESET}"
    printf '%b       Spark + Iceberg Quickstart Container Manager%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '%b=================================================================%b\n' "${COLOR_BLUE}" "${COLOR_RESET}"
    printf ' Runtime: %-10s Project: %s\n\n' "${RUNTIME}" "${PROJECT_DIR}"

    printf '%bContainer Management%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    print_menu_row "1) Install / Clone Project" "2) Start Environment"
    print_menu_row "3) Stop Environment" "4) Restart Environment"
    print_menu_row "5) Show Status" "6) Show Ports"
    print_menu_row "7) Show Logs" "8) Tail Logs"
    print_menu_row "9) Pull / Update" "10) Build Image"

    printf '\n%bWeb Interfaces%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    print_menu_row "11) Open Jupyter" "12) Open Spark UI"
    print_menu_row "13) Open MinIO Console" "14) Open Iceberg REST"
    print_menu_row "15) Show Credentials" "16) Health Check"

    printf '\n%bMinIO / Oracle Object Storage%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    print_menu_row "17) Show S3 Information" "18) Test Oracle S3 Endpoint"
    print_menu_row "19) Connect Oracle Container" "20) Show Local CA"
    print_menu_row "21) Regenerate TLS" "22) Show Compose Config"

    printf '\n%bShell Access%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    print_menu_row "23) Container Shell" "24) PySpark Shell"
    print_menu_row "25) Spark SQL Shell" "26) Scala Spark Shell"
    print_menu_row "27) MinIO Shell" "Q) Quit"

    printf '\n%bDestroy Area%b\n' "${COLOR_RED}" "${COLOR_RESET}"
    print_menu_row "28) Remove Containers" ""
    printf '\n'
}

interactive_menu() {
    local choice

    while true; do
        show_menu
        read -r -p "Select an option: " choice
        printf '\n'

        case "${choice}" in
            1) install_project; pause ;;
            2) start_stack; pause ;;
            3) stop_stack; pause ;;
            4) restart_stack; pause ;;
            5) show_status; pause ;;
            6) show_ports; pause ;;
            7) show_logs; pause ;;
            8) tail_logs; pause ;;
            9) update_project; pause ;;
            10) build_images; pause ;;
            11) open_service "${JUPYTER_URL}"; pause ;;
            12) open_service "${SPARK_UI_URL}"; pause ;;
            13) open_service "${MINIO_CONSOLE_URL}"; pause ;;
            14) open_service "${ICEBERG_REST_URL}"; pause ;;
            15) show_credentials; pause ;;
            16) health_check; pause ;;
            17) show_s3_info; pause ;;
            18) test_s3_access; pause ;;
            19) prompt_connect_oracle; pause ;;
            20) show_ca_info; pause ;;
            21) regenerate_tls; pause ;;
            22) show_config; pause ;;
            23) spark_shell ;;
            24) pyspark_shell ;;
            25) spark_sql_shell ;;
            26) scala_shell ;;
            27) minio_shell ;;
            28) remove_stack; pause ;;
            q|Q|quit|exit) return 0 ;;
            *) warn "Invalid selection: ${choice}"; pause ;;
        esac
    done
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [command] [arguments]

Commands:
  menu                    Open the interactive menu (default)
  install                 Clone the upstream project if it is not present
  start                   Start all services in the background
  stop                    Stop all services without removing them
  restart                 Restart the environment
  status                  Show Compose service status
  ports                   Show local and container-network endpoints
  logs                    Show the latest service logs
  tail                    Follow service logs
  update                  Fast-forward the repository and pull images
  build                   Build the Spark image from source
  jupyter                 Open Jupyter Notebook
  sparkui                 Open the Spark UI
  minio                   Open the MinIO console
  catalog                 Open the Iceberg REST endpoint
  credentials             Show development credentials and S3 endpoints
  health                  Check host endpoints and Oracle-facing S3 access
  s3info                  Show MinIO/S3 and Oracle container connection details
  tests3                  Test HTTPS/S3 access through the shared network
  connectoracle [name]      Attach Oracle ADB (default: myadb) and install the local CA
  cainfo                  Show the generated local CA details
  regeneratetls           Regenerate the local CA and TLS server certificate
  shell                   Open Bash in the Spark container
  pyspark                 Open a PySpark shell
  sparksql                Open a Spark SQL shell
  scala                   Open a Scala Spark shell
  minioshell              Open a shell in the MinIO container
  config                  Render the effective Compose configuration
  remove                  Remove Compose containers; preserve MinIO object data
  doctor                  Check prerequisites and integration configuration
  help                    Show this help

Environment variables:
  SPARK_ICEBERG_HOME            Project checkout directory
  SPARK_ICEBERG_REPOSITORY_URL  Alternate Git repository URL
  SPARK_ICEBERG_NETWORK         Shared network (default: oracle-datalake)
  SPARK_ICEBERG_MINIO_VOLUME    Named MinIO data volume
  SPARK_ICEBERG_TLS_PROXY_IMAGE TLS proxy image (default: nginx:alpine)
  SPARK_ICEBERG_MC_IMAGE        MinIO client image (default: minio/mc:latest)
  ORACLE_ADB_CONTAINER          Oracle ADB container (default: myadb)
  CONTAINER_ENGINE              Force 'docker' or 'podman'

Examples:
  $(basename "$0") install
  $(basename "$0") start
  $(basename "$0") s3info
  $(basename "$0") tests3
  $(basename "$0") connectoracle adb-free
  $(basename "$0") health
  $(basename "$0") stop
EOF
}

main() {
    local action="${1:-menu}"
    if [[ $# -gt 0 ]]; then
        shift
    fi

    case "${action}" in
        help|-h|--help)
            usage
            return 0
            ;;
        version|-v|--version)
            printf '%s\n' "${SCRIPT_VERSION}"
            return 0
            ;;
    esac

    if [[ "${action}" == "doctor" ]]; then
        doctor
        return $?
    fi

    detect_runtime || return 1

    case "${action}" in
        menu) interactive_menu ;;
        install) install_project ;;
        start) start_stack ;;
        stop) stop_stack ;;
        restart) restart_stack ;;
        status) show_status ;;
        ports) show_ports ;;
        logs) show_logs ;;
        tail) tail_logs ;;
        update|pull) update_project ;;
        build) build_images ;;
        jupyter) open_service "${JUPYTER_URL}" ;;
        sparkui) open_service "${SPARK_UI_URL}" ;;
        minio) open_service "${MINIO_CONSOLE_URL}" ;;
        catalog) open_service "${ICEBERG_REST_URL}" ;;
        credentials|creds) show_credentials ;;
        health) health_check ;;
        s3info) show_s3_info ;;
        tests3|tests3access) test_s3_access ;;
        connectoracle|oracleconnect) connect_oracle_container "${1:-}" ;;
        cainfo|ca) show_ca_info ;;
        regeneratetls|tlsreset) regenerate_tls ;;
        shell) spark_shell ;;
        pyspark) pyspark_shell ;;
        sparksql) spark_sql_shell ;;
        scala|sparkshell) scala_shell ;;
        minioshell) minio_shell ;;
        config) show_config ;;
        remove) remove_stack ;;
        *)
            error "Unknown command: ${action}"
            usage
            return 2
            ;;
    esac
}

main "$@"

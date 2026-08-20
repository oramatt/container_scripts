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
#   - Preserve local notebooks and warehouse data during container removal
#
# REQUIREMENTS:
#   - Bash 4 or later
#   - Git installed and available in PATH
#   - Docker with Docker Compose v2, or Podman with a Compose provider
#   - curl for HTTP endpoint health checks
#   - Internet connectivity for the initial clone and container image pulls
#   - Free local ports 8080, 8181, 8888, 9000, 9001, 10000, and 10001
#
# NOTES:
#   - Intended for local Spark and Apache Iceberg learning and development
#   - This environment is not a local installation of the Databricks platform
#   - Jupyter authentication is disabled by the upstream quickstart image
#   - MinIO uses development credentials; do not expose it to untrusted networks
#   - Review port mappings, bind mounts, and environment variables before use
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
#   1.0.0
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

SCRIPT_VERSION="1.0.0"
REPOSITORY_URL="${SPARK_ICEBERG_REPOSITORY_URL:-https://github.com/databricks/docker-spark-iceberg.git}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
    DEFAULT_PROJECT_DIR="${SCRIPT_DIR}"
else
    DEFAULT_PROJECT_DIR="${SCRIPT_DIR}/docker-spark-iceberg"
fi

PROJECT_DIR="${SPARK_ICEBERG_HOME:-${DEFAULT_PROJECT_DIR}}"
COMPOSE_FILE="${PROJECT_DIR}/docker-compose.yml"
SPARK_SERVICE="spark-iceberg"

JUPYTER_URL="http://localhost:8888"
SPARK_UI_URL="http://localhost:8080"
ICEBERG_REST_URL="http://localhost:8181"
MINIO_API_URL="http://localhost:9000"
MINIO_CONSOLE_URL="http://localhost:9001"

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

compose() {
    ensure_project || return 1
    (
        cd "${PROJECT_DIR}" || exit 1
        "${COMPOSE_CMD[@]}" "$@"
    )
}

stack_exists() {
    compose ps -q 2>/dev/null | grep -q .
}

service_running() {
    local container_id
    container_id="$(compose ps -q "${SPARK_SERVICE}" 2>/dev/null)"
    [[ -n "${container_id}" ]] || return 1
    [[ "$("${RUNTIME}" inspect -f '{{.State.Running}}' "${container_id}" 2>/dev/null)" == "true" ]]
}

install_project() {
    ensure_project || return 1
    success "Project is available at ${PROJECT_DIR}"
}

start_stack() {
    runtime_ready || return 1
    ensure_project || return 1

    info "Starting the Spark + Iceberg environment with ${COMPOSE_CMD[*]}"
    compose up -d || return 1
    success "Spark + Iceberg environment started."
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

    printf '%bThis removes the Compose containers and network.%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
    printf 'The bind-mounted notebooks and warehouse directory will be preserved.\n'
    read -r -p "Type REMOVE to continue: " confirmation
    if [[ "${confirmation}" != "REMOVE" ]]; then
        warn "Remove cancelled."
        return 0
    fi

    compose down --remove-orphans && success "Compose containers and network removed."
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
    printf '%-22s %-25s %s\n' "SERVICE" "LOCAL ENDPOINT" "PURPOSE"
    printf '%-22s %-25s %s\n' "--------------------" "-----------------------" "-----------------------------"
    printf '%-22s %-25s %s\n' "Jupyter Notebook" "${JUPYTER_URL}" "PySpark and Scala notebooks"
    printf '%-22s %-25s %s\n' "Spark UI" "${SPARK_UI_URL}" "Spark master and job visibility"
    printf '%-22s %-25s %s\n' "Iceberg REST" "${ICEBERG_REST_URL}" "Iceberg REST catalog"
    printf '%-22s %-25s %s\n' "MinIO API" "${MINIO_API_URL}" "S3-compatible object storage"
    printf '%-22s %-25s %s\n' "MinIO Console" "${MINIO_CONSOLE_URL}" "Object-storage administration"
    printf '%-22s %-25s %s\n' "Spark Thrift" "localhost:10000" "Spark SQL Thrift/JDBC"
    printf '%-22s %-25s %s\n' "Spark Thrift HTTP" "localhost:10001" "Spark Thrift HTTP transport"
}

show_credentials() {
    cat <<'EOF'
Jupyter Notebook
  Username: none
  Password: none
  Token:    disabled by the upstream image

MinIO Console and S3-compatible API
  Username / Access key: admin
  Password / Secret key: password

Spark UI and Iceberg REST catalog
  Authentication: none

WARNING: These development services are not secured for public exposure.
EOF
}

show_endpoints() {
    printf '\n'
    show_ports
    printf '\nMinIO credentials: admin / password\n'
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
    if ! service_running; then
        warn "The Spark service does not appear to be running."
        warn "Start it with: $0 start"
        return 1
    fi
    open_url "${url}"
}

spark_exec() {
    runtime_ready || return 1
    if ! service_running; then
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
    compose exec minio sh
}

health_check() {
    local failed=0

    runtime_ready || return 1
    show_status
    printf '\nEndpoint checks:\n'

    if ! command -v curl >/dev/null 2>&1; then
        warn "curl is unavailable; skipping HTTP endpoint checks."
        return 0
    fi

    while IFS='|' read -r name url; do
        if curl --silent --show-error --location --max-time 5 --output /dev/null "${url}"; then
            printf '  %-20s %bAVAILABLE%b\n' "${name}" "${COLOR_GREEN}" "${COLOR_RESET}"
        else
            printf '  %-20s %bUNAVAILABLE%b\n' "${name}" "${COLOR_RED}" "${COLOR_RESET}"
            failed=1
        fi
    done <<EOF
Jupyter|${JUPYTER_URL}
Spark UI|${SPARK_UI_URL}
Iceberg REST|${ICEBERG_REST_URL}
MinIO API|${MINIO_API_URL}/minio/health/live
MinIO Console|${MINIO_CONSOLE_URL}
EOF

    return "${failed}"
}

doctor() {
    printf 'Spark + Iceberg Manager diagnostics\n'
    printf '  Script version: %s\n' "${SCRIPT_VERSION}"
    printf '  Project path:   %s\n' "${PROJECT_DIR}"
    printf '  Repository:     %s\n' "${REPOSITORY_URL}"

    if detect_runtime; then
        printf '  Runtime:        %s\n' "${RUNTIME}"
        printf '  Compose:        %s\n' "${COMPOSE_CMD[*]}"
    else
        return 1
    fi

    if [[ -f "${COMPOSE_FILE}" ]]; then
        printf '  Compose file:   FOUND\n'
    else
        printf '  Compose file:   NOT INSTALLED\n'
    fi

    runtime_ready
}

print_menu_row() {
    printf '  %-38s %s\n' "$1" "$2"
}

show_menu() {
    clear 2>/dev/null || true
    printf '%b===============================================================%b\n' "${COLOR_BLUE}" "${COLOR_RESET}"
    printf '%b       Spark + Iceberg Quickstart Container Manager%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '%b===============================================================%b\n' "${COLOR_BLUE}" "${COLOR_RESET}"
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
    printf '\n%bShell Access%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    print_menu_row "17) Container Shell" "18) PySpark Shell"
    print_menu_row "19) Spark SQL Shell" "20) Scala Spark Shell"
    print_menu_row "21) MinIO Shell" "22) Show Compose Config"
    printf '\n%bDestroy Area%b\n' "${COLOR_RED}" "${COLOR_RESET}"
    print_menu_row "23) Remove Containers" "Q) Quit"
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
            17) spark_shell ;;
            18) pyspark_shell ;;
            19) spark_sql_shell ;;
            20) scala_shell ;;
            21) minio_shell ;;
            22) show_config; pause ;;
            23) remove_stack; pause ;;
            q|Q|quit|exit) return 0 ;;
            *) warn "Invalid selection: ${choice}"; pause ;;
        esac
    done
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [command]

Commands:
  menu          Open the interactive menu (default)
  install       Clone the upstream project if it is not present
  start         Start all services in the background
  stop          Stop all services without removing them
  restart       Restart the environment
  status        Show Compose service status
  ports         Show local ports and endpoints
  logs          Show the latest service logs
  tail          Follow service logs
  update        Fast-forward the repository and pull images
  build         Build the Spark image from source
  jupyter       Open Jupyter Notebook
  sparkui       Open the Spark UI
  minio         Open the MinIO console
  catalog       Open the Iceberg REST endpoint
  credentials   Show development credentials
  health        Check container and HTTP endpoint health
  shell         Open Bash in the Spark container
  pyspark       Open a PySpark shell
  sparksql      Open a Spark SQL shell
  scala         Open a Scala Spark shell
  minioshell    Open a shell in the MinIO container
  config        Render the effective Compose configuration
  remove        Remove Compose containers and network; preserve local data
  doctor        Check prerequisites and configuration
  help          Show this help

Environment variables:
  SPARK_ICEBERG_HOME            Project checkout directory
  SPARK_ICEBERG_REPOSITORY_URL  Alternate Git repository URL
  CONTAINER_ENGINE              Force 'docker' or 'podman'

Examples:
  $(basename "$0") install
  $(basename "$0") start
  $(basename "$0") jupyter
  $(basename "$0") pyspark
  $(basename "$0") stop
EOF
}

main() {
    local action="${1:-menu}"

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

#!/usr/bin/env bash
# register-scanner.sh — Register a remote scanner node with the central gvmd
#
# Usage:
#   ./scripts/register-scanner.sh <scanner-host> [scanner-port] [scanner-name]
#
# Prerequisites:
#   - The portal stack must be running (portal/compose.yaml)
#   - The scanner node must be running and reachable (scanner/compose.yaml)
#   - gvm-tools is available in the portal's gvm-tools container
#
# Examples:
#   Register a single remote scanner:
#     ./scripts/register-scanner.sh 192.168.1.50
#
#   Register with a custom port and name:
#     ./scripts/register-scanner.sh 192.168.1.50 9390 "Remote Scanner - Site A"

set -euo pipefail

SCANNER_HOST="${1:?Usage: $0 <scanner-host> [scanner-port] [scanner-name]}"
SCANNER_PORT="${2:-9390}"
SCANNER_NAME="${3:-Remote Scanner (${SCANNER_HOST}:${SCANNER_PORT})}"

# Credentials for the gvmd management API.
# Override GMP_USERNAME / GMP_PASSWORD in the environment or in portal/.env
# rather than storing them in this script.
GMP_USERNAME="${GMP_USERNAME:-admin}"
GMP_PASSWORD="${GMP_PASSWORD:?Set GMP_PASSWORD in your environment or portal/.env}"

COMPOSE_FILE="$(dirname "$0")/../portal/compose.yaml"

echo "Registering scanner '${SCANNER_NAME}' at ${SCANNER_HOST}:${SCANNER_PORT} ..."

docker compose -f "${COMPOSE_FILE}" run --rm gvm-tools \
  gvm-cli \
    --gmp-username "${GMP_USERNAME}" \
    --gmp-password "${GMP_PASSWORD}" \
    socket \
    --socketpath /run/gvmd/gvmd.sock \
    --xml "<create_scanner>
              <name>${SCANNER_NAME}</name>
              <host>${SCANNER_HOST}</host>
              <port>${SCANNER_PORT}</port>
              <type>2</type>
            </create_scanner>"

echo "Done. The scanner '${SCANNER_NAME}' has been registered."
echo "It will appear under Configuration → Scanners in the Greenbone Security Assistant."

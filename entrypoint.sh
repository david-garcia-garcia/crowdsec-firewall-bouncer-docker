#!/bin/bash
set -eu

# CrowdSec Firewall Bouncer Entrypoint Script
# Processes configuration template with envsubst and starts the bouncer
#
# Configuration paths (hardcoded):
# - Template: /tmp/crowdsec-config-source/crowdsec-firewall-bouncer.yaml.template
# - Output: /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml

CONFIG_DIR="/etc/crowdsec/bouncers"
CONFIG_FILE="${CONFIG_DIR}/crowdsec-firewall-bouncer.yaml"
CONFIG_TEMPLATE_PATH="/tmp/crowdsec-config-source/crowdsec-firewall-bouncer.yaml.template"

echo "Starting CrowdSec Firewall Bouncer..."

# Detect system firewall backend
if command -v iptables >/dev/null 2>&1; then
    IPTABLES_OUTPUT=$(iptables -V 2>&1 || true)
    if echo "$IPTABLES_OUTPUT" | grep -qi 'nf_tables'; then
        DETECTED_MODE="nftables"
    else
        DETECTED_MODE="iptables"
    fi
    
    # Warn if detected mode doesn't match configured mode
    if [ -n "${NETWORK_MODE:-}" ] && [ "$DETECTED_MODE" != "$NETWORK_MODE" ]; then
        echo "WARNING: System is using $DETECTED_MODE but this image is configured for $NETWORK_MODE"
        echo "WARNING: The bouncer may not function correctly. Consider using the $DETECTED_MODE variant."
    else
        echo "Detected firewall backend: $DETECTED_MODE (matches configured mode: ${NETWORK_MODE:-unknown})"
    fi
fi

# Set defaults for environment variables if not set
export CROWDSEC_API_URL="${CROWDSEC_API_URL:-http://127.0.0.1:8080}"
if [ -z "${CROWDSEC_API_KEY:-}" ]; then
    echo "Error: CROWDSEC_API_KEY is required but not set"
    exit 1
fi

# Process config template with envsubst
if [ ! -f "${CONFIG_TEMPLATE_PATH}" ]; then
    echo "Error: Configuration template not found at ${CONFIG_TEMPLATE_PATH}"
    exit 1
fi

echo "Processing configuration template with environment variables..."
# Collect all environment variables that start with CROWDSEC_ for substitution
CROWDSEC_VARS=$(env | grep '^CROWDSEC_' | cut -d= -f1 | sed 's/^/${/' | sed 's/$/}/' | tr '\n' ' ')
# Substitute all CROWDSEC_* environment variables
envsubst "$CROWDSEC_VARS" < "${CONFIG_TEMPLATE_PATH}" > "${CONFIG_FILE}"
echo "Configuration file generated successfully from template"

# Ensure configuration file was created successfully
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "Error: Failed to generate configuration file at ${CONFIG_FILE}"
    exit 1
fi

# Environment variables are validated and defaults set above

# Start the bouncer
echo "Starting crowdsec-firewall-bouncer..."
exec crowdsec-firewall-bouncer -c "${CONFIG_FILE}"

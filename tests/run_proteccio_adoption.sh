#!/bin/bash

# OpenStack 17.1 to RHOSO 18 Adoption with Proteccio HSM
# Automated execution script for dp-adopt framework

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration file for customizable paths and settings
CONFIG_FILE="${CONFIG_FILE:-config.env}"

# Default values (can be overridden via config file or environment variables)
PROTECCIO_BASE_DIR="${PROTECCIO_BASE_DIR:-$HOME/adopt_proteccio}"
PROTECCIO_ROLES_DIR="${PROTECCIO_ROLES_DIR:-$PROTECCIO_BASE_DIR/roles/ansible-role-rhoso-proteccio-hsm}"
PROTECCIO_FILES_DIR="${PROTECCIO_FILES_DIR:-$PROTECCIO_BASE_DIR/proteccio_files}"
INVENTORY_FILE="${INVENTORY_FILE:-inventory.proteccio.yaml}"
PLAYBOOK_FILE="${PLAYBOOK_FILE:-playbooks/barbican_proteccio_adoption.yml}"
EXPECTED_USER="${EXPECTED_USER:-stack}"

# Load configuration file if it exists
if [[ -f "$CONFIG_FILE" ]]; then
    echo "Loading configuration from $CONFIG_FILE..."
    source "$CONFIG_FILE"
fi

echo "============================================="
echo "OpenStack 17.1 to RHOSO 18 Adoption"
echo "with Proteccio HSM Integration"
echo "Using barbican_proteccio_adoption role"
echo "============================================="
echo "NOTE: This is for Proteccio HSM environments only"
echo "For standard adoptions, use the regular dp-adopt framework"
echo "============================================="
echo "Configuration:"
echo "  Proteccio base directory: $PROTECCIO_BASE_DIR"
echo "  Proteccio roles directory: $PROTECCIO_ROLES_DIR"
echo "  Proteccio files directory: $PROTECCIO_FILES_DIR"
echo "  Expected user: $EXPECTED_USER"
echo "============================================="
echo

# Verify prerequisites
echo "Checking prerequisites..."

if [[ "$USER" != "$EXPECTED_USER" ]]; then
    echo "ERROR: ERROR: This script must be run as the '$EXPECTED_USER' user"
    exit 1
fi

if ! command -v ansible-playbook &> /dev/null; then
    echo "ERROR: ERROR: ansible-playbook not found"
    exit 1
fi

if ! command -v oc &> /dev/null; then
    echo "ERROR: ERROR: oc not found"
    exit 1
fi

if ! oc cluster-info &> /dev/null; then
    echo "ERROR: ERROR: Cannot connect to Kubernetes cluster"
    exit 1
fi

if [[ ! -d "$PROTECCIO_ROLES_DIR" ]]; then
    echo "ERROR: ERROR: Proteccio HSM Ansible role not found at $PROTECCIO_ROLES_DIR"
    echo "Set PROTECCIO_ROLES_DIR environment variable or update config.env"
    exit 1
fi

if [[ ! -d "$PROTECCIO_FILES_DIR" ]]; then
    echo "ERROR: ERROR: proteccio_files directory not found at $PROTECCIO_FILES_DIR"
    echo "Set PROTECCIO_FILES_DIR environment variable or update config.env"
    exit 1
fi

# Check required proteccio files based on role configuration
echo "Checking for required Proteccio files..."
if [[ -f "roles/barbican_proteccio_adoption/defaults/main.yml" ]]; then
    # Extract required files from the role defaults if possible
    REQUIRED_FILES=$(grep -A 20 "proteccio_required_files:" roles/barbican_proteccio_adoption/defaults/main.yml | grep '^\s*-\s*"' | sed 's/.*"\(.*\)".*/\1/' | grep -v "CHANGE_ME" || echo "")

    if [[ -n "$REQUIRED_FILES" ]]; then
        for file in $REQUIRED_FILES; do
            if [[ ! -f "$PROTECCIO_FILES_DIR/$file" ]]; then
                echo "WARNING:️  WARNING: File $PROTECCIO_FILES_DIR/$file not found"
                echo "   Update proteccio_required_files in your role configuration"
            fi
        done
    else
        echo "WARNING:️  WARNING: No configured certificate files found to check"
        echo "   Ensure proteccio_required_files is properly configured in your role variables"
        echo "   and that all CHANGE_ME placeholders have been replaced"
    fi
else
    echo "WARNING:️  WARNING: Could not find role defaults file to check required files"
    echo "   Ensure you have configured proteccio_required_files in your role variables"
fi

if [[ ! -f "roles/barbican_proteccio_adoption/tasks/main.yml" ]]; then
    echo "ERROR: ERROR: Adoption role not found in roles/barbican_proteccio_adoption"
    exit 1
fi

if [[ ! -f "$INVENTORY_FILE" ]]; then
    echo "ERROR: ERROR: Inventory file not found: $INVENTORY_FILE"
    echo "Set INVENTORY_FILE environment variable or update config.env"
    exit 1
fi

if [[ ! -f "$PLAYBOOK_FILE" ]]; then
    echo "ERROR: ERROR: Playbook file not found: $PLAYBOOK_FILE"
    echo "Set PLAYBOOK_FILE environment variable or update config.env"
    exit 1
fi

echo "✓ All prerequisites verified"
echo

# Display options
echo "Adoption Options:"
echo "1. Full adoption (all phases)"
echo "2. Run specific phase only"
echo "3. Dry run (check mode)"
echo

read -p "Select option (1-3) [1]: " OPTION
OPTION=${OPTION:-1}

case $OPTION in
    1)
        echo "Running full adoption..."
        ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK_FILE"
        ;;
    2)
        echo "Available phases:"
        echo "  - phase1 (preparation)"
        echo "  - phase2 (base_deployment)"
        echo "  - phase3 (database_adoption)"
        echo "  - phase4 (proteccio_deployment)"
        echo "  - phase5 (verification)"
        echo
        read -p "Enter phase to run: " PHASE
        ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK_FILE" --tags "$PHASE"
        ;;
    3)
        echo "Running dry run..."
        ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK_FILE" --check
        ;;
    *)
        echo "ERROR: Invalid option"
        exit 1
        ;;
esac

echo
echo "============================================="
echo "Adoption execution completed!"
echo "Check the generated summary file for details"
echo "============================================="

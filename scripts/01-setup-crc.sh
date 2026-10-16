#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PULL_SECRET_FILE="${1:-${WORKSPACE_ROOT}/pull-secret.json}"

echo "=========================================================="
echo " Red Hat OpenShift Local (CRC) Setup & Launch"
echo "=========================================================="

if ! command -v crc &>/dev/null; then
    echo "ERROR: 'crc' is not installed in PATH."
    exit 1
fi

if ! command -v oc &>/dev/null; then
    echo "ERROR: 'oc' is not installed in PATH."
    exit 1
fi

echo "[1/4] Checking and setting CRC configuration..."
crc config set consent-telemetry no
crc config set cpus 8
crc config set memory 24576
crc config set disk-size 80
crc config view

echo ""
echo "[2/4] Running 'crc setup' to ensure hypervisor and bundles are ready..."
crc setup

echo ""
echo "[3/4] Checking for Red Hat Pull Secret..."
if [[ ! -f "${PULL_SECRET_FILE}" ]]; then
    echo "----------------------------------------------------------------------"
    echo "A Red Hat pull secret is required to start OpenShift Local."
    echo "1. Visit https://console.redhat.com/openshift/create/local"
    echo "2. Log in with your Red Hat account (or create a free account)."
    echo "3. Click 'Download pull secret'."
    echo "4. Save it as '${WORKSPACE_ROOT}/pull-secret.json' or provide its path:"
    echo "   $0 /path/to/pull-secret.txt"
    echo "----------------------------------------------------------------------"
    read -rp "Enter the absolute path to your pull secret file (or paste JSON directly): " USER_INPUT
    if [[ -f "${USER_INPUT}" ]]; then
        PULL_SECRET_FILE="${USER_INPUT}"
    elif [[ "${USER_INPUT}" =~ ^\{.*\}$ ]]; then
        echo "${USER_INPUT}" > "${WORKSPACE_ROOT}/pull-secret.json"
        PULL_SECRET_FILE="${WORKSPACE_ROOT}/pull-secret.json"
        echo "Saved pull secret to ${PULL_SECRET_FILE}"
    else
        echo "ERROR: File '${USER_INPUT}' does not exist and input is not valid JSON."
        exit 1
    fi
fi

echo "Using pull secret: ${PULL_SECRET_FILE}"

echo ""
echo "[4/4] Starting OpenShift Local cluster..."
crc start --pull-secret-file "${PULL_SECRET_FILE}"

echo ""
echo "Setting up oc environment credentials..."
eval "$(crc oc-env)"

if [[ -f "${HOME}/.crc/machines/crc/kubeconfig" ]]; then
    export KUBECONFIG="${HOME}/.crc/machines/crc/kubeconfig"
elif [[ -f "${HOME}/.crc/cache/crc_vfkit_4.22.14_arm64/kubeconfig" ]]; then
    export KUBECONFIG="${HOME}/.crc/cache/crc_vfkit_4.22.14_arm64/kubeconfig"
fi

echo "Logging in as kubeadmin..."
KUBEADMIN_PASSWORD=$(crc console --credentials | grep -i kubeadmin | awk '{print $NF}' || true)
if [[ -n "${KUBEADMIN_PASSWORD}" ]]; then
    oc login -u kubeadmin -p "${KUBEADMIN_PASSWORD}" https://api.crc.testing:6443 --insecure-skip-tls-verify=true || true
fi

echo ""
echo "Cluster is running!"
oc whoami || true
oc version || true
echo ""
echo "Web console URL and login credentials can be checked anytime with:"
echo "  crc console --credentials"


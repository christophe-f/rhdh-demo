#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
MANIFESTS_DIR="$(cd "${SCRIPT_DIR}/../manifests" && pwd)"

echo "=========================================================="
echo " [Step 2] Deploying Keycloak (Red Hat build of Keycloak)"
echo "=========================================================="

echo "Creating namespace 'rhdh-auth' and subscribing to Keycloak Operator..."
oc apply -f "${MANIFESTS_DIR}/02-keycloak/01-namespace.yaml"

echo "Waiting for Keycloak operator to be ready in rhdh-auth..."
op_attempts=0
while [[ $op_attempts -lt 40 ]]; do
    csv=$(oc get csv -n rhdh-auth --no-headers -o custom-columns=":metadata.name" 2>/dev/null | grep -E "^rhbk-operator" | head -n 1 || true)
    if [[ -n "${csv}" ]]; then
        phase=$(oc get csv "${csv}" -n rhdh-auth -o jsonpath='{.status.phase}' 2>/dev/null || true)
        if [[ "${phase}" == "Succeeded" ]]; then
            echo "  ✔ Keycloak Operator (${csv}) is installed!"
            break
        fi
    fi
    sleep 5
    op_attempts=$((op_attempts + 1))
done

echo "Deploying PostgreSQL backend for Keycloak..."
oc apply -f "${MANIFESTS_DIR}/02-keycloak/02-db.yaml"

echo "Waiting for PostgreSQL pod to be ready..."
oc rollout status deployment/keycloak-db -n rhdh-auth --timeout=180s

echo "Deploying Keycloak instance..."
oc apply -f "${MANIFESTS_DIR}/02-keycloak/03-keycloak.yaml"

echo "Waiting for Keycloak deployment to be ready..."
local_attempts=0
while [[ $local_attempts -lt 40 ]]; do
    if oc get deployment -n rhdh-auth -l app.kubernetes.io/name=rhdh-keycloak &>/dev/null; then
        oc rollout status deployment -n rhdh-auth -l app.kubernetes.io/name=rhdh-keycloak --timeout=120s && break
    fi
    echo "  ... waiting for Keycloak deployment to be created"
    sleep 5
    local_attempts=$((local_attempts + 1))
done

echo "Importing RHDH Realm, Client, and Test Users..."
oc apply -f "${MANIFESTS_DIR}/02-keycloak/04-realm-rhdh.yaml"

KEYCLOAK_HOST=$(oc get route -n rhdh-auth -l app=rhdh-keycloak -o jsonpath='{.items[0].spec.host}' 2>/dev/null || echo "")
if [[ -z "${KEYCLOAK_HOST}" ]]; then
    KEYCLOAK_HOST=$(oc get route rhdh-keycloak-service -n rhdh-auth -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
fi

echo ""
echo "Keycloak deployment complete!"
echo "Keycloak Host: https://${KEYCLOAK_HOST}"
echo "Test Developer Account: developer / developer123!"
echo "Test Admin Account:     platform-admin / admin123!"

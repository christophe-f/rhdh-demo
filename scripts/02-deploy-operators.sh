#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
MANIFESTS_DIR="$(cd "${SCRIPT_DIR}/../manifests" && pwd)"

echo "=========================================================="
echo " [Step 1] Deploying Red Hat Operators via OperatorHub"
echo "=========================================================="

echo "Verifying cluster connection..."
oc whoami

echo ""
echo "Discovering default channels from OperatorHub Catalog..."

get_default_channel() {
    local pkg="$1"
    local fallback="$2"
    local channel
    channel=$(oc get packagemanifest "${pkg}" -n openshift-marketplace -o jsonpath='{.status.defaultChannel}' 2>/dev/null || echo "")
    if [[ -z "${channel}" ]]; then
        echo "${fallback}"
    else
        echo "${channel}"
    fi
}

PIPELINES_CHANNEL=$(get_default_channel "openshift-pipelines-operator-rh" "latest")
GITOPS_CHANNEL=$(get_default_channel "openshift-gitops-operator" "latest")
RHDH_CHANNEL=$(get_default_channel "rhdh" "fast")

echo "Selected Operator Channels:"
echo " - Pipelines (Tekton): ${PIPELINES_CHANNEL}"
echo " - GitOps (Argo CD):   ${GITOPS_CHANNEL}"
echo " - Developer Hub:      ${RHDH_CHANNEL}"

echo ""
echo "Creating/updating subscriptions..."

create_subscription() {
    local name="$1"
    local pkg="$2"
    local channel="$3"
    cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ${name}
  namespace: openshift-operators
spec:
  channel: ${channel}
  installPlanApproval: Automatic
  name: ${pkg}
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
}

create_subscription "openshift-pipelines-operator-rh" "openshift-pipelines-operator-rh" "${PIPELINES_CHANNEL}"
create_subscription "openshift-gitops-operator" "openshift-gitops-operator" "${GITOPS_CHANNEL}"
create_subscription "rhdh" "rhdh" "${RHDH_CHANNEL}"

echo ""
echo "Waiting for operators to install..."

wait_for_csv() {
    local prefix="$1"
    local namespace="$2"
    echo "Checking status for operator matching '${prefix}' in '${namespace}'..."
    local attempts=0
    local max_attempts=40
    while [[ $attempts -lt $max_attempts ]]; do
        local csv
        csv=$(oc get csv -n "${namespace}" --no-headers -o custom-columns=":metadata.name" 2>/dev/null | grep -E "^${prefix}" | head -n 1 || true)
        if [[ -n "${csv}" ]]; then
            local phase
            phase=$(oc get csv "${csv}" -n "${namespace}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
            if [[ "${phase}" == "Succeeded" ]]; then
                echo "  ✔ ${csv} is installed (Phase: Succeeded)"
                return 0
            else
                echo "  ... ${csv} phase is '${phase}' (waiting...)"
            fi
        else
            echo "  ... waiting for subscription to generate ClusterServiceVersion '${prefix}'"
        fi
        sleep 10
        attempts=$((attempts + 1))
    done
    echo "WARNING: Timed out waiting for ${prefix} CSV. It may still be installing in the background."
}

wait_for_csv "openshift-pipelines-operator-rh" "openshift-operators"
wait_for_csv "openshift-gitops-operator" "openshift-operators"
wait_for_csv "rhdh" "openshift-operators"

echo ""
echo "All operator subscriptions submitted and verified!"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================================="
echo " Starting Full Red Hat Developer Hub Stack Deployment"
echo "=========================================================="

echo ""
echo ">>> [1/3] Deploying Operators..."
"${SCRIPT_DIR}/02-deploy-operators.sh"

echo ""
echo ">>> [2/3] Deploying Keycloak SSO & Authentication..."
"${SCRIPT_DIR}/03-deploy-keycloak.sh"

echo ""
echo ">>> [3/3] Deploying PostgreSQL & Red Hat Developer Hub..."
"${SCRIPT_DIR}/04-deploy-rhdh.sh"

echo ""
echo "All steps completed successfully!"

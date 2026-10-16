#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
MANIFESTS_DIR="$(cd "${SCRIPT_DIR}/../manifests" && pwd)"

echo "=========================================================="
echo " [Step 3] Deploying Red Hat Developer Hub (RHDH)"
echo "=========================================================="

echo "Creating namespace 'rhdh'..."
oc apply -f "${MANIFESTS_DIR}/03-postgresql/01-namespace.yaml"

echo "Deploying PostgreSQL backend for RHDH..."
oc apply -f "${MANIFESTS_DIR}/03-postgresql/02-postgresql.yaml"
oc rollout status deployment/rhdh-postgresql -n rhdh --timeout=180s
echo "Ensuring rhdh role has CREATEDB permission for dynamic plugin schemas..."
oc exec -n rhdh deployment/rhdh-postgresql -- psql -U postgres -c "ALTER ROLE rhdh CREATEDB;" 2>/dev/null || true


echo ""
echo "Discovering cluster endpoints and credentials..."

# 1. Discover Keycloak Route
KEYCLOAK_HOST=$(oc get route rhdh-keycloak -n rhdh-auth -o jsonpath='{.spec.host}' 2>/dev/null || echo "rhdh-keycloak-rhdh-auth.apps-crc.testing")
echo "Keycloak Host: ${KEYCLOAK_HOST}"

# 2. Discover Argo CD Route
ARGOCD_HOST=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
echo "ArgoCD Host:   ${ARGOCD_HOST}"

# Get ArgoCD admin password or auth token
ARGOCD_PASSWORD=$(oc get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' 2>/dev/null | base64 -d || echo "admin")

# 3. Create ServiceAccount for RHDH Kubernetes/Topology/Tekton integration
echo "Setting up RHDH ServiceAccount and ClusterRoleBinding..."
oc create serviceaccount rhdh-sa -n rhdh --dry-run=client -o yaml | oc apply -f -
oc create clusterrolebinding rhdh-sa-view --clusterrole=view --serviceaccount=rhdh:rhdh-sa --dry-run=client -o yaml | oc apply -f -
oc create clusterrolebinding rhdh-sa-pipelines --clusterrole=pipelines-scc-clusterrole --serviceaccount=rhdh:rhdh-sa --dry-run=client -o yaml 2>/dev/null || true

# Extract SA Token
K8S_SA_TOKEN=$(oc create token rhdh-sa -n rhdh --duration=8760h 2>/dev/null || oc serviceaccounts get-token rhdh-sa -n rhdh 2>/dev/null || echo "demo-token")

# 4. Generate random backend and session secrets
BACKEND_SECRET=$(openssl rand -hex 16 2>/dev/null || echo "b4ck3nd-s3cr3t-k3y-123456789012")
SESSION_SECRET=$(openssl rand -hex 16 2>/dev/null || echo "s3ss10n-s3cr3t-k3y-123456789012")
KEYCLOAK_CLIENT_SECRET="rhdh-secret-key-12345"

# 5. Pre-create the RHDH Route to know its hostname
APPS_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "apps-crc.testing")
RHDH_HOST="backstage-rhdh-rhdh.${APPS_DOMAIN}"
echo "Predicted RHDH Host: ${RHDH_HOST}"

# 6. Create rhdh-secrets
echo "Creating rhdh-secrets Secret..."
oc create secret generic rhdh-secrets -n rhdh \
  --from-literal=RHDH_HOST="${RHDH_HOST}" \
  --from-literal=KEYCLOAK_HOST="${KEYCLOAK_HOST}" \
  --from-literal=KEYCLOAK_CLIENT_SECRET="${KEYCLOAK_CLIENT_SECRET}" \
  --from-literal=ARGOCD_HOST="${ARGOCD_HOST}" \
  --from-literal=ARGOCD_TOKEN="${ARGOCD_PASSWORD}" \
  --from-literal=K8S_SA_TOKEN="${K8S_SA_TOKEN}" \
  --from-literal=BACKEND_SECRET="${BACKEND_SECRET}" \
  --from-literal=SESSION_SECRET="${SESSION_SECRET}" \
  --from-literal=POSTGRESQL_USER="rhdh" \
  --from-literal=POSTGRESQL_PASSWORD="rhdhpassword123!" \
  --from-literal=POSTGRESQL_DATABASE="rhdh" \
  --from-literal=NODE_TLS_REJECT_UNAUTHORIZED="0" \
  --dry-run=client -o yaml | oc apply -f -

# 7. Deploy Golden Path Templates
echo "Deploying Golden Path Templates server..."
oc create configmap template-quarkus-root -n rhdh \
  --from-file="${PROJECT_ROOT}/templates/golden-paths/quarkus-service/template.yaml" \
  --dry-run=client -o yaml | oc apply -f -
oc create configmap template-quarkus-skeleton -n rhdh \
  --from-file="${PROJECT_ROOT}/templates/golden-paths/quarkus-service/skeleton/catalog-info.yaml" \
  --from-file="${PROJECT_ROOT}/templates/golden-paths/quarkus-service/skeleton/pom.xml" \
  --from-file="${PROJECT_ROOT}/templates/golden-paths/quarkus-service/skeleton/README.md" \
  --dry-run=client -o yaml | oc apply -f -
oc create configmap template-quarkus-java -n rhdh \
  --from-file=GreetingResource.java="${PROJECT_ROOT}/templates/golden-paths/quarkus-service/skeleton/src/main/java/org/acme/GreetingResource.java" \
  --from-file=application.properties="${PROJECT_ROOT}/templates/golden-paths/quarkus-service/skeleton/src/main/resources/application.properties" \
  --dry-run=client -o yaml | oc apply -f -
oc create configmap template-quarkus-ci -n rhdh \
  --from-file=pipeline.yaml="${PROJECT_ROOT}/templates/golden-paths/quarkus-service/skeleton/tekton/pipeline.yaml" \
  --from-file=application.yaml="${PROJECT_ROOT}/templates/golden-paths/quarkus-service/skeleton/argocd/application.yaml" \
  --dry-run=client -o yaml | oc apply -f -
oc apply -f "${MANIFESTS_DIR}/04-rhdh/05-catalog-users.yaml"
oc apply -f "${MANIFESTS_DIR}/05-templates/01-templates-server.yaml"
oc rollout status deployment/rhdh-templates-server -n rhdh --timeout=120s

# 8. Apply AppConfig and Dynamic Plugins
echo "Applying ConfigMaps..."
oc apply -f "${MANIFESTS_DIR}/04-rhdh/01-app-config.yaml"
oc apply -f "${MANIFESTS_DIR}/04-rhdh/02-dynamic-plugins.yaml"

# 9. Deploy Backstage Custom Resource
echo "Deploying Red Hat Developer Hub Custom Resource..."
oc apply -f "${MANIFESTS_DIR}/04-rhdh/04-backstage.yaml"

echo "Waiting for Backstage deployment to be ready..."
oc rollout status deployment/backstage-rhdh -n rhdh --timeout=300s

ACTUAL_RHDH_ROUTE=$(oc get route backstage-rhdh -n rhdh -o jsonpath='{.spec.host}' 2>/dev/null || echo "${RHDH_HOST}")


echo ""
echo "=========================================================="
echo "🎉 Red Hat Developer Hub is deployed successfully!"
echo "=========================================================="
echo "RHDH URL:        https://${ACTUAL_RHDH_ROUTE}"
echo "Keycloak URL:    https://${KEYCLOAK_HOST}"
echo "ArgoCD URL:      https://${ARGOCD_HOST}"
echo ""
echo "Login via Keycloak (OIDC):"
echo "  Username: developer"
echo "  Password: developer123!"
echo ""
echo "Admin Login:"
echo "  Username: platform-admin"
echo "  Password: admin123!"
echo "=========================================================="

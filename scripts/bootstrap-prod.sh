#!/bin/bash
set -euo pipefail

# scripts/bootstrap-prod.sh - Bootstrap the production cluster (Netcup)
# Usage: ./scripts/bootstrap-prod.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../versions.env"

echo "🚀 Bootstrapping Production Cluster (Netcup)..."

# 1. Check Prerequisites
echo "🔍 Checking prerequisites..."
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ kubectl cannot connect to cluster. Please configure your KUBECONFIG."
    exit 1
fi

# 2. Apply Bootstrap Manifests (CRDs, Namespaces, RBAC)
echo "📦 Applying bootstrap manifests..."
cd "${SCRIPT_DIR}/../infra/bootstrap"

echo "  - Applying CRDs..."
kubectl apply --server-side --force-conflicts -k crds/

echo "  - Waiting for CRDs..."
kubectl get crd -o name | grep -E 'cert-manager.io|traefik.io|acme.cert-manager.io|bitnami.com|argoproj.io|gateway.networking.k8s.io|monitoring.coreos.com' | \
  xargs kubectl wait --for=condition=Established --timeout=180s

echo "  - Applying Namespaces, RBAC, Middlewares..."
kubectl apply -k namespaces/
kubectl apply -f rbac/gh-actions.yaml
kubectl apply -k middlewares/

# 3. Install Core Components via Helmfile (Direct Mode)
echo "🛠️ Installing Core Components (Cert-Manager, SealedSecrets, ArgoCD)..."
cd "${SCRIPT_DIR}/../infra/apps"

# Install Cert-Manager first
echo "  - Installing Cert-Manager..."
helmfile --environment netcup --selector name=cert-manager apply --suppress-secrets

echo "  - Waiting for Cert-Manager..."
kubectl wait deployment -n cert-manager --all --for=condition=Available --timeout=300s

# Install SealedSecrets
echo "  - Installing SealedSecrets..."
helmfile --environment netcup --selector name=sealed-secrets apply --suppress-secrets

echo "  - Waiting for SealedSecrets..."
kubectl wait deployment -n kube-system -l app.kubernetes.io/name=sealed-secrets --for=condition=Available --timeout=300s

# Install Traefik
echo "  - Installing Traefik..."
helmfile --environment netcup --selector name=traefik apply --suppress-secrets

echo "  - Waiting for Traefik..."
kubectl wait deployment -n traefik --all --for=condition=Available --timeout=300s

# Install ArgoCD
echo "  - Installing ArgoCD..."
helmfile --environment netcup --selector name=argocd apply --suppress-secrets

echo "  - Waiting for ArgoCD..."
kubectl wait deployment -n argocd --all --for=condition=Available --timeout=300s

# 4. Apply Secrets (todos los *-sealed.yaml presentes en bootstrap/secrets)
echo "🔐 Applying Sealed Secrets..."
cd "${SCRIPT_DIR}/../infra/bootstrap"
for sealed in secrets/*-sealed.yaml; do
    [ -e "$sealed" ] || continue
    kubectl apply -f "$sealed"
done

# Los SealedSecrets solo se dessellan en el cluster contra el que se generaron.
# Si falta alguno, genéralo con el contexto kubectl apuntando a ESTE cluster:
#   ./scripts/generate-credentials.sh --component all
for required in grafana-admin-sealed.yaml admin-basic-auth-sealed.yaml cloudflare-api-token-sealed.yaml argocd-redis-sealed.yaml; do
    if [ ! -f "secrets/${required}" ]; then
        echo "⚠️  Falta secrets/${required}; genera con: ./scripts/generate-credentials.sh --component all"
    fi
done

# 5. Create the ArgoCD ApplicationSet (GitOps entry point for netcup):
#    genera una Application por cada infra/apps/<app>/app.yaml
echo "🎯 Applying ArgoCD ApplicationSet (cluster-apps)..."
kubectl apply -f appset-netcup.yaml

# 6. Final Status
echo ""
echo "✅ Bootstrap completed successfully!"
echo "ArgoCD should now be running. You can verify with:"
echo "  kubectl get pods -n argocd"
echo "  kubectl get applications -n argocd -l cluster=netcup"
echo ""
echo "The CI pipeline should now be able to connect and sync."

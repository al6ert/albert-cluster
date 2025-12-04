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
kubectl apply -k crds/ --validate=false

echo "  - Waiting for CRDs..."
kubectl get crd -o name | grep -E 'cert-manager.io|traefik.io|acme.cert-manager.io|bitnami.com|argoproj.io' | \
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

# 4. Apply Secrets (if any exist in bootstrap/secrets)
echo "🔐 Applying Sealed Secrets..."
cd "${SCRIPT_DIR}/../infra/bootstrap"
if [ -d "secrets" ]; then
    if [ -f "secrets/kustomization.yaml" ]; then
        kubectl apply -k secrets/
    else
        kubectl apply -f secrets/
    fi
fi

# 5. Final Status
echo ""
echo "✅ Bootstrap completed successfully!"
echo "ArgoCD should now be running. You can verify with:"
echo "  kubectl get pods -n argocd"
echo ""
echo "The CI pipeline should now be able to connect and sync."

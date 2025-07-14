#!/bin/bash
set -euo pipefail

# deploy-local.sh - Idempotent local deployment script
# This script deploys the GitOps cluster to a local Kubernetes environment (minikube)

# Source versions from centralized file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/versions.env"

echo "🚀 Starting idempotent local deployment..."
echo "📋 Using versions: Helm ${HELM_VERSION}, Helmfile ${HELMFILE_VERSION}"

# Helper functions
check_prerequisites() {
    echo "🔍 Checking prerequisites..."

    # Check if kubectl is available and cluster is accessible
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo "❌ kubectl cannot connect to cluster. Please ensure minikube is running."
        exit 1
    fi

    # Check if helmfile is available
    if ! command -v helmfile >/dev/null 2>&1; then
        echo "❌ helmfile not found. Please install helmfile first."
        echo "   Install with: curl -Lo helmfile https://github.com/helmfile/helmfile/releases/download/${HELMFILE_VERSION}/helmfile_linux_amd64"
        exit 1
    fi

    echo "✅ Prerequisites check passed"
}

wait_for_crds() {
    local timeout=${1:-120}
    echo "⏳ Waiting for CRDs to be established (timeout: ${timeout}s)..."

    # Get all CRDs we expect to be present
    local expected_crds="cert-manager.io traefik.io acme.cert-manager.io bitnami.com argoproj.io"

    for pattern in $expected_crds; do
        echo "  - Waiting for $pattern CRDs..."
        kubectl get crd -o name | grep -E "$pattern" | \
            xargs -r kubectl wait --for=condition=Established --timeout="${timeout}s" || {
            echo "    ⚠️ Some $pattern CRDs not ready, continuing..."
        }
    done

    echo "✅ CRD establishment phase completed"
}

wait_for_sealed_secrets() {
    echo "🔓 Waiting for SealedSecrets to be unsealed..."

    # Get all SealedSecrets and wait for their corresponding Secrets to be created
    while IFS= read -r ss_info; do
        if [ -n "$ss_info" ]; then
            local ns
            local name
            ns=$(echo "$ss_info" | cut -d' ' -f1)
            name=$(echo "$ss_info" | cut -d' ' -f2)
            echo "  - Waiting for $name in namespace $ns..."

            # Wait for SealedSecret to be processed
            kubectl wait sealedsecret/"$name" -n "$ns" --for=condition=Sealed=true --timeout=60s || {
                echo "    ⚠️ SealedSecret $name unsealing timed out"
            }
        fi
    done < <(kubectl get sealedsecrets -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

    echo "✅ SealedSecrets processing completed"
}

apply_bootstrap() {
    echo "📦 Applying bootstrap resources (idempotent)..."
    cd "${SCRIPT_DIR}/infra/bootstrap"

    echo "::group::Phase 1: Namespaces, CRDs, and RBAC"
    kubectl apply -k namespaces/
    kubectl apply -k crds/ --validate=false
    kubectl apply -f rbac/gh-actions.yaml
    echo "::endgroup::"

    wait_for_crds "$@"

    echo "::group::Phase 2: Secrets and Middlewares"
    kubectl apply -k secrets/
    kubectl apply -k middlewares/
    echo "::endgroup::"

    wait_for_sealed_secrets

    echo "::group::Phase 3: ArgoCD Applications (optional for local)"
    if [[ "${DEPLOY_ARGOCD_APPS:-true}" == "true" ]]; then
        kubectl apply -f argocd-minikube.yaml --validate=false
        echo "✅ ArgoCD applications applied"
    else
        echo "⚠️ Skipping ArgoCD applications (DEPLOY_ARGOCD_APPS=false)"
    fi
    echo "::endgroup::"

    echo "✅ Bootstrap phase completed"
}

deploy_applications() {
    echo "🚀 Deploying applications with Helmfile..."
    cd "${SCRIPT_DIR}/infra/apps"

    # Export versions for Helmfile templates
    export TRAEFIK_CHART_VERSION
    export CERT_MANAGER_CHART_VERSION
    export SEALED_SECRETS_CHART_VERSION
    export HELLO_CHART_VERSION

    # Apply applications idempotently
    helmfile --environment minikube apply --suppress-secrets

    echo "⏳ Waiting for all deployments to be ready..."
    kubectl wait deployment --all -A --for=condition=Available --timeout=300s || {
        echo "⚠️ Some deployments not ready within timeout, checking individual status..."
        kubectl get deployments -A | grep -E "(0/|False)"
    }

    echo "✅ Application deployment completed"
}

show_status() {
    echo "📊 Cluster Status Summary:"
    echo "  Namespaces: $(kubectl get ns | grep -c -E '(admin|argocd|cert-manager|traefik|hello)')"
    echo "  Pods Running: $(kubectl get pods -A --field-selector=status.phase=Running | wc -l)"
    echo "  CRDs: $(kubectl get crd | grep -c -E '(cert-manager|traefik|bitnami|argoproj)')"
    echo "  SealedSecrets: $(kubectl get sealedsecrets -A --no-headers 2>/dev/null | wc -l)"

    echo ""
    echo "🌐 Access URLs:"
    echo "  Traefik Dashboard: https://traefik.127.0.0.1.nip.io/dashboard/"
    echo "  Hello App: http://hello.127.0.0.1.nip.io"
    echo ""
    echo "🔐 Default credentials: admin / admin"
    echo ""
    echo "💡 To check pod status: kubectl get pods -A"
    echo "💡 To check application logs: kubectl logs -n traefik -l app.kubernetes.io/name=traefik"
}

main() {
    check_prerequisites
    apply_bootstrap
    deploy_applications
    show_status

    echo "🎉 Local deployment completed successfully!"
}

# Allow sourcing this script for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

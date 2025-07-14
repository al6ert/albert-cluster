#!/bin/bash
set -euo pipefail

# scripts/deploy.sh - Idempotent GitOps deployment script
# Usage: ./scripts/deploy.sh [minikube|netcup]

# Source versions from centralized file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../versions.env"

ENVIRONMENT=${1:-minikube}

# Validate environment
if [[ "$ENVIRONMENT" != "minikube" && "$ENVIRONMENT" != "netcup" ]]; then
    echo "❌ Invalid environment. Usage: $0 [minikube|netcup]"
    exit 1
fi

echo "🚀 Starting GitOps deployment for environment: $ENVIRONMENT"
echo "📋 Using versions: Helm ${HELM_VERSION}, Helmfile ${HELMFILE_VERSION}"

# Helper functions
check_prerequisites() {
    echo "🔍 Checking prerequisites..."

    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo "❌ kubectl cannot connect to cluster"
        exit 1
    fi

    if ! command -v helmfile >/dev/null 2>&1; then
        echo "❌ helmfile not found. Install it first:"
        echo "   curl -Lo helmfile https://github.com/helmfile/helmfile/releases/download/${HELMFILE_VERSION}/helmfile_linux_amd64"
        exit 1
    fi

    echo "✅ Prerequisites check passed"
}

validate_manifests() {
    local env=$1
    echo "🔍 Validating manifests for $env..."

    cd "${SCRIPT_DIR}/../infra/apps"

    # Export versions for template rendering
    export TRAEFIK_CHART_VERSION
    export CERT_MANAGER_CHART_VERSION
    export SEALED_SECRETS_CHART_VERSION
    export HELLO_CHART_VERSION

    # Create temp directory for validation
    mkdir -p "../tmp"

    # Render templates for validation
    echo "  - Rendering templates..."
    helmfile --environment "$env" template > "../tmp/${env}-validation.yaml"

    # Validate YAML syntax
    echo "  - Validating YAML syntax..."
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import yaml, sys
try:
    with open('../tmp/${env}-validation.yaml') as f:
        list(yaml.safe_load_all(f))
    print('✅ YAML syntax is valid')
except yaml.YAMLError as e:
    print(f'❌ YAML syntax error: {e}')
    sys.exit(1)
        "
    else
        echo "⚠️ Python3 not found, skipping YAML validation"
    fi

    # Helmfile lint
    echo "  - Running helmfile lint..."
    helmfile --environment "$env" lint

    echo "✅ Manifest validation completed"
}

check_argocd_status() {
    echo "🔍 Checking ArgoCD status..."

    if ! kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server --no-headers 2>/dev/null | grep -q Running; then
        echo "⚠️ ArgoCD is not running or not found"
        echo "💡 For pure GitOps mode, ArgoCD should be running"
        echo "💡 You can still deploy directly with Helmfile"
        return 1
    fi

    echo "✅ ArgoCD is running"
    return 0
}

deploy_with_helmfile() {
    local env=$1
    echo "🚀 Deploying with Helmfile (direct mode)..."

    cd "${SCRIPT_DIR}/../infra/apps"

    # Export versions for Helmfile
    export TRAEFIK_CHART_VERSION
    export CERT_MANAGER_CHART_VERSION
    export SEALED_SECRETS_CHART_VERSION
    export HELLO_CHART_VERSION

    # Deploy applications
    helmfile --environment "$env" apply --suppress-secrets

    echo "⏳ Waiting for deployments to be ready..."
    kubectl wait deployment --all -A --for=condition=Available --timeout=300s || {
        echo "⚠️ Some deployments not ready, checking status..."
        kubectl get deployments -A | grep -E "(0/|False)" || echo "All deployments appear ready"
    }

    echo "✅ Helmfile deployment completed"
}

trigger_argocd_sync() {
    local env=$1
    echo "🔄 Triggering ArgoCD sync..."

    local app_name
    if [[ "$env" == "minikube" ]]; then
        app_name="cluster-minikube"
    else
        app_name="cluster-root"
    fi

    # Check if ArgoCD CLI is available
    if command -v argocd >/dev/null 2>&1; then
        echo "  - Using ArgoCD CLI for sync"
        # Note: This requires argocd login to be done beforehand
        argocd app sync "$app_name" --prune --self-heal || {
            echo "⚠️ ArgoCD CLI sync failed, falling back to kubectl patch"
            trigger_sync_via_kubectl "$app_name"
        }
    else
        echo "  - ArgoCD CLI not found, using kubectl patch"
        trigger_sync_via_kubectl "$app_name"
    fi
}

trigger_sync_via_kubectl() {
    local app_name=$1
    echo "  - Triggering sync via kubectl patch..."

    # Force refresh by patching the application
    kubectl patch application "$app_name" -n argocd --type='merge' \
        -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"'"$(date +%s)"'"}}}' || {
        echo "⚠️ Failed to patch ArgoCD application"
    }
}

check_deployment_status() {
    local env=$1
    echo "📊 Checking deployment status for $env..."

    echo "  Cluster Info:"
    echo "    Context: $(kubectl config current-context)"
    echo "    Namespaces: $(kubectl get ns | grep -c -E '(admin|argocd|cert-manager|traefik|hello)')"
    echo "    Running Pods: $(kubectl get pods -A --field-selector=status.phase=Running --no-headers | wc -l)"

    if [[ "$env" == "minikube" ]]; then
        echo ""
        echo "🌐 Local Access URLs:"
        echo "    Traefik Dashboard: https://traefik.127.0.0.1.nip.io/dashboard/"
        echo "    Hello App: http://hello.127.0.0.1.nip.io"
        echo "    Default credentials: admin / admin"
    else
        echo ""
        echo "🌐 Production Access URLs:"
        echo "    Traefik Dashboard: https://traefik.albertperez.dev/dashboard/"
        echo "    Hello App: https://hello.albertperez.dev"
    fi

    echo ""
    echo "💡 Useful commands:"
    echo "    Check apps: kubectl get applications -n argocd"
    echo "    Check pods: kubectl get pods -A"
    echo "    Check logs: kubectl logs -n traefik -l app.kubernetes.io/name=traefik"
}

main() {
    check_prerequisites
    validate_manifests "$ENVIRONMENT"

    echo ""
    echo "🎯 Manifests validated successfully"
    echo "📤 Deploying applications..."

    # Try GitOps approach first, fallback to direct deployment
    if check_argocd_status; then
        echo "🔄 Using GitOps mode (ArgoCD)"
        trigger_argocd_sync "$ENVIRONMENT"
    else
        echo "🔧 Using direct mode (Helmfile)"
        deploy_with_helmfile "$ENVIRONMENT"
    fi

    check_deployment_status "$ENVIRONMENT"

    echo ""
    echo "🎉 GitOps deployment completed successfully!"
}

# Allow sourcing this script for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

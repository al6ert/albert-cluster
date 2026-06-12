#!/bin/bash
set -euo pipefail

# deploy-local.sh - Idempotent local deployment script
# This script deploys the GitOps cluster to a local Kubernetes environment (minikube)

# Source versions from centralized file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/versions.env"

# Disable default minikube ingress addon if enabled to avoid conflicts with Traefik
if minikube addons list | grep -q "ingress: enabled"; then
    echo "Disabling default minikube ingress addon to avoid conflicts..."
    minikube addons disable ingress
fi

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

    # Check if kubeseal is available
    if ! command -v kubeseal >/dev/null 2>&1; then
        echo "❌ kubeseal not found. Please install kubeseal first."
        echo "   Install with: curl -Lo kubeseal https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION#v}/kubeseal-darwin-amd64 && chmod +x kubeseal && sudo mv kubeseal /usr/local/bin/"
        exit 1
    fi

    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        echo "❌ jq not found. Please install jq first."
        echo "   Install with: brew install jq (on macOS) or apt-get install jq (on Linux)"
        exit 1
    fi

    echo "✅ Prerequisites check passed"
}

wait_for_crds() {
    local timeout=${1:-120}
    echo "⏳ Waiting for CRDs to be established (timeout: ${timeout}s)..."

    # Get all CRDs we expect to be present
    local expected_crds="cert-manager.io traefik.io acme.cert-manager.io bitnami.com argoproj.io gateway.networking.k8s.io monitoring.coreos.com"

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

    # List of secret_name:namespace pairs without associative array (for Bash 3.x compatibility)
    local sealed_secrets=(
        "admin-basic-auth:admin"
        "cloudflare-api-token:cert-manager"
        "grafana-admin:monitoring"
    )

    for item in "${sealed_secrets[@]}"; do
        local secret_name="${item%:*}"
        local ns="${item#*:}"
        echo "  - Waiting for $secret_name in namespace $ns..."

        # Wait for Secret to exist and have data
        # (kubectl wait --for=jsonpath no sirve aquí: .data es un mapa y nunca
        # sería igual al literal "non-empty")
        local unsealed=false
        for _ in $(seq 1 60); do
            if [ -n "$(kubectl get secret "$secret_name" -n "$ns" -o jsonpath='{.data}' 2>/dev/null)" ]; then
                unsealed=true
                break
            fi
            sleep 2
        done
        if [ "$unsealed" != "true" ]; then
            echo "    ⚠️ Secret $secret_name not unsealed within timeout"
            # Debug: Check logs
            kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets --tail=50 | grep "$secret_name" || echo "No logs found for $secret_name"
        fi
    done

    echo "✅ SealedSecrets processing completed"
}

apply_bootstrap() {
    echo "📦 Applying bootstrap resources (idempotent)..."
    cd "${SCRIPT_DIR}/infra/bootstrap"

    echo "::group::Phase 1: Namespaces, CRDs, and RBAC"
    kubectl apply -k namespaces/
    kubectl apply --server-side --force-conflicts -k crds/
    kubectl apply -f rbac/gh-actions.yaml
    echo "::endgroup::"

    wait_for_crds

    echo "::group::Phase 2: Middlewares (before secrets)"
    kubectl apply -k middlewares/
    echo "::endgroup::"

    echo "::group::Phase 2.5: SealedSecrets Controller"
    echo "Installing SealedSecrets controller before secrets..."
    cd "${SCRIPT_DIR}/infra/apps/sealed-secrets"

    # Export versions for Helmfile templates
    export SEALED_SECRETS_CHART_VERSION
    helmfile --environment minikube apply --suppress-secrets

    echo "⏳ Waiting for SealedSecrets controller to be ready..."
    kubectl wait deployment sealed-secrets -n kube-system --for=condition=Available --timeout=300s

    cd "${SCRIPT_DIR}/infra/bootstrap"
    echo "::endgroup::"

    echo "::group::Phase 2.6: Generate and apply fresh SealedSecrets"
    # Sellados locales a un dir temporal para NO pisar los *-sealed.yaml del
    # repo (que están sellados contra el cluster de producción)
    LOCAL_SECRETS_DIR=$(mktemp -d)

    # Generate admin-basic-auth using the script (defaults: namespace=admin, users=admin)
    SECRETS_DIR="$LOCAL_SECRETS_DIR" \
        bash "${SCRIPT_DIR}/scripts/generate-credentials.sh" --component basic-auth --namespace admin --users admin --secret-name admin-basic-auth
    kubectl apply -f "${LOCAL_SECRETS_DIR}/admin-basic-auth-sealed.yaml"

    # Grafana admin (admin/admin para desarrollo local, salvo override en .env.local)
    SECRETS_DIR="$LOCAL_SECRETS_DIR" GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin}" \
        bash "${SCRIPT_DIR}/scripts/generate-credentials.sh" --component grafana
    kubectl apply -f "${LOCAL_SECRETS_DIR}/grafana-admin-sealed.yaml"

    # Generate cloudflare-api-token with dummy for local
    echo "Generating dummy Cloudflare API token secret for local..."
    TMP_SECRET_YAML=$(mktemp)
    cat > "$TMP_SECRET_YAML" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token
  namespace: cert-manager
type: Opaque
stringData:
  api-token: dummy-cloudflare-token
EOF
    TMP_SEALED_YAML=$(mktemp)
    kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system --format yaml < "$TMP_SECRET_YAML" > "$TMP_SEALED_YAML"
    kubectl apply -f "$TMP_SEALED_YAML"
    rm -f "$TMP_SECRET_YAML" "$TMP_SEALED_YAML"
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

# Los Services LoadBalancer (Traefik) necesitan una IP; sin ella helm --wait
# se bloquea hasta timeout. En vez de depender de `minikube tunnel` (requiere
# sudo interactivo), habilitamos el addon metallb con un rango de la red de
# minikube (idempotente).
ensure_loadbalancer() {
    if ! minikube addons list | grep -q "metallb: enabled"; then
        echo "🔌 Enabling metallb addon for LoadBalancer support..."
        minikube addons enable metallb
    fi
    local prefix
    prefix=$(minikube ip | cut -d. -f1-3)
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: config
  namespace: metallb-system
data:
  config: |
    address-pools:
      - name: default
        protocol: layer2
        addresses:
          - ${prefix}.100-${prefix}.120
EOF
}

deploy_applications() {
    echo "🚀 Deploying applications with Helmfile..."
    cd "${SCRIPT_DIR}/infra/apps"

    # Export versions for Helmfile templates
    export TRAEFIK_CHART_VERSION
    export CERT_MANAGER_CHART_VERSION
    export SEALED_SECRETS_CHART_VERSION
    export HELLO_CHART_VERSION
    export ARGOCD_CHART_VERSION
    export PROMETHEUS_CHART_VERSION

    # Apply applications idempotently (excluding SealedSecrets as it's already installed in bootstrap)
    helmfile --environment minikube apply --suppress-secrets --selector 'name!=sealed-secrets'

    echo "⏳ Waiting for all deployments to be ready..."
    kubectl wait deployment --all -A --for=condition=Available --timeout=300s || {
        echo "⚠️ Some deployments not ready within timeout, checking individual status..."
        kubectl get deployments -A | grep -E "(0/|False)"
    }

    echo "✅ Application deployment completed"
}

show_status() {
    echo "📊 Cluster Status Summary:"
    echo "  Namespaces: $(kubectl get ns | grep -E '(admin|argocd|cert-manager|traefik|hello)' | wc -l)"
    echo "  Pods Running: $(kubectl get pods -A --field-selector=status.phase=Running | wc -l)"
    echo "  CRDs: $(kubectl get crd | grep -E '(cert-manager|traefik|bitnami|argoproj)' | wc -l)"
    echo "  SealedSecrets: $(kubectl get sealedsecrets -A --no-headers 2>/dev/null | wc -l)"
    echo ""
    echo "🌐 Access URLs (Ingress):"
    kubectl get ingress --all-namespaces -o json | jq -r '
      .items[] | . as $ingress |
      .spec.rules[]? |
      "  - " + .host + (.http.paths[]? | "\(.path) => namespace: \($ingress.metadata.namespace), svc: \($ingress.spec.rules[0].http.paths[0].backend.service.name)")'
    echo ""
    # Mostrar credenciales generadas si existen
    PASSWORDS_FILE="/tmp/admin-basic-auth-passwords.txt"
    if [ -f "$PASSWORDS_FILE" ]; then
        echo "🔑 Basic Auth credentials (from $PASSWORDS_FILE):"
        cat "$PASSWORDS_FILE"
        echo ""
    else
        echo "⚠️  No se encontró el archivo de contraseñas generadas ($PASSWORDS_FILE). Si necesitas las credenciales, revisa la salida de generate-credentials.sh."
        echo ""
    fi
    # Mostrar password real de ArgoCD
    ARGOCD_PWD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode || kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.admin\\.password}' 2>/dev/null | base64 --decode)
    if [ -n "$ARGOCD_PWD" ]; then
        echo "🔑 ArgoCD admin password: $ARGOCD_PWD"
        echo "  Login: https://argo.127.0.0.1.nip.io (user: admin)"
    else
        echo "⚠️  No se pudo obtener el password de ArgoCD admin."
    fi
    echo ""
    echo "💡 To check pod status: kubectl get pods -A"
    echo "💡 To check application logs: kubectl logs -n traefik -l app.kubernetes.io/name=traefik"
}

main() {
    check_prerequisites
    apply_bootstrap
    ensure_loadbalancer
    deploy_applications
    show_status

    echo "🎉 Local deployment completed successfully!"
}

# Allow sourcing this script for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

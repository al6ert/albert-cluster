#!/bin/bash
set -euo pipefail

# scripts/generate-credentials.sh - Punto único de generación de credenciales.
# Genera Secrets y los sella con kubeseal contra el cluster del contexto kubectl
# actual (los SealedSecrets solo se pueden dessellar en ese cluster).
#
# Usage:
#   ./scripts/generate-credentials.sh [--component basic-auth|grafana|cloudflare|argocd-redis|grafana-cloud|all] [opciones]
#
# Componentes:
#   basic-auth  htpasswd para el dashboard de Traefik (default; namespace admin)
#   grafana     credenciales admin de Grafana (Secret grafana-admin, namespace monitoring)
#   cloudflare  token de API de Cloudflare para cert-manager (requiere CLOUDFLARE_API_TOKEN)
#   argocd-redis password de auth del Redis de ArgoCD (Secret argocd-redis, namespace argocd)
#   grafana-cloud credenciales de Grafana Cloud para Alloy (Secret grafana-cloud-credentials,
#               namespace monitoring; requiere GRAFANA_CLOUD_PROM_USER/LOKI_USER/TOKEN)
#   velero      credenciales S3 de R2 para backups (Secret velero-r2-credentials,
#               namespace velero; requiere R2_ACCESS_KEY_ID/R2_SECRET_ACCESS_KEY)
#   all         todos salvo grafana-cloud y velero (requieren cuenta externa; generar aparte)
#
# Passwords fijos via .env.local (no versionado): ADMIN_PASSWORD, ARGO_PASSWORD,
# GRAFANA_ADMIN_PASSWORD, CLOUDFLARE_API_TOKEN. Sin ellos se generan aleatorios
# (excepto cloudflare, que exige token real).

# Source versions from centralized file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../versions.env"

# Por defecto escribe en el repo (para sellar contra prod y commitear);
# deploy-local.sh lo redirige a un dir temporal para no pisar los sellados de prod.
SECRETS_DIR="${SECRETS_DIR:-${SCRIPT_DIR}/../infra/bootstrap/secrets}"

# Cargar passwords fijos desde .env.local si existe
ENV_LOCAL_FILE="${SCRIPT_DIR}/../.env.local"
if [ -f "$ENV_LOCAL_FILE" ]; then
    # Exporta las variables definidas en .env.local
    set -a
    . "$ENV_LOCAL_FILE"
    set +a
fi

# Default values (can be overridden)
COMPONENT="${COMPONENT:-basic-auth}"
NAMESPACE="${NAMESPACE:-admin}"
USERS="${USERS:-admin,argo}"
SECRET_NAME="${SECRET_NAME:-admin-basic-auth}"
BCRYPT_ROUNDS="${BCRYPT_ROUNDS:-12}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --component)
            COMPONENT="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --users)
            USERS="$2"
            shift 2
            ;;
        --secret-name)
            SECRET_NAME="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--component basic-auth|grafana|cloudflare|all] [--namespace NS] [--users \"u1,u2\"] [--secret-name NAME]"
            echo ""
            echo "Environment variables (.env.local):"
            echo "  ADMIN_PASSWORD, ARGO_PASSWORD        basic-auth"
            echo "  GRAFANA_ADMIN_PASSWORD               grafana"
            echo "  CLOUDFLARE_API_TOKEN                 cloudflare (obligatoria)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    if ! command -v openssl >/dev/null 2>&1; then
        echo "❌ openssl not found. Please install openssl."
        exit 1
    fi

    if [[ "$COMPONENT" == "basic-auth" || "$COMPONENT" == "all" ]] && ! command -v htpasswd >/dev/null 2>&1; then
        echo "❌ htpasswd not found. Please install apache2-utils."
        exit 1
    fi

    if ! command -v kubeseal >/dev/null 2>&1; then
        echo "❌ kubeseal not found. Install it with:"
        echo "   curl -Lo kubeseal https://github.com/bitnami/sealed-secrets/releases/download/v${KUBESEAL_VERSION#v}/kubeseal-linux-amd64"
        echo "   chmod +x kubeseal && sudo mv kubeseal /usr/local/bin/"
        exit 1
    fi
}

# Create secure temporary directory
setup_temp_dir() {
    TMP_DIR=$(mktemp -d)
    trap "rm -rf '$TMP_DIR'" EXIT
}

# Sella un Secret (stdin: ruta a yaml; stdout: fichero sellado en SECRETS_DIR)
seal_secret_file() {
    local secret_file="$1"
    local sealed_file="$2"
    mkdir -p "$SECRETS_DIR"
    kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system \
        --format yaml < "$secret_file" > "$sealed_file"
    echo "✅ SealedSecret created at $sealed_file"
}

# --- basic-auth (dashboard de Traefik) -------------------------------------
generate_basic_auth() {
    echo "🔐 [basic-auth] Generating htpasswd credentials (ns=$NAMESPACE, users=$USERS)..."

    local htpasswd_file="$TMP_DIR/users.htpasswd"
    rm -f "$htpasswd_file"

    IFS=',' read -ra USER_ARRAY <<< "$USERS"
    PASSWORDS_FILE="$TMP_DIR/passwords.txt"
    > "$PASSWORDS_FILE"

    for user in "${USER_ARRAY[@]}"; do
        user=$(echo "$user" | xargs)  # trim whitespace
        # Si hay password fijo en env, úsalo
        case "$user" in
            admin)
                password="${ADMIN_PASSWORD:-}"
                ;;
            argo)
                password="${ARGO_PASSWORD:-}"
                ;;
            *)
                password=""
                ;;
        esac
        if [ -z "$password" ]; then
            password=$(openssl rand -base64 20)
        fi
        echo "$user:$password" >> "$PASSWORDS_FILE"
        echo "🔑 $user: $password"
        htpasswd -nbBC "$BCRYPT_ROUNDS" "$user" "$password" >> "$htpasswd_file"
    done
    # Copiar el archivo de passwords a /tmp para que deploy-local.sh lo muestre
    cp "$PASSWORDS_FILE" /tmp/admin-basic-auth-passwords.txt

    local secret_file="$TMP_DIR/${SECRET_NAME}-secret.yaml"
    cat > "$secret_file" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/managed-by: kubeseal
    app.kubernetes.io/component: basic-auth
type: Opaque
stringData:
  users: |
$(sed 's/^/    /' "$htpasswd_file")
EOF

    seal_secret_file "$secret_file" "${SECRETS_DIR}/${SECRET_NAME}-sealed.yaml"
}

# --- grafana (admin de Grafana, consumido via grafana.admin.existingSecret) -
generate_grafana() {
    echo "🔐 [grafana] Generating Grafana admin credentials (ns=monitoring)..."

    local user="${GRAFANA_ADMIN_USER:-admin}"
    local password="${GRAFANA_ADMIN_PASSWORD:-}"
    if [ -z "$password" ]; then
        password=$(openssl rand -base64 20)
    fi
    echo "🔑 grafana/$user: $password"

    local secret_file="$TMP_DIR/grafana-admin-secret.yaml"
    cat > "$secret_file" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: grafana-admin
  namespace: monitoring
  labels:
    app.kubernetes.io/managed-by: kubeseal
    app.kubernetes.io/component: grafana
type: Opaque
stringData:
  admin-user: ${user}
  admin-password: ${password}
EOF

    seal_secret_file "$secret_file" "${SECRETS_DIR}/grafana-admin-sealed.yaml"
}

# --- argocd-redis (auth del Redis de ArgoCD; sustituye al Job redis-secret-init) ---
generate_argocd_redis() {
    echo "🔐 [argocd-redis] Generating ArgoCD Redis auth secret (ns=argocd)..."

    local password="${ARGOCD_REDIS_PASSWORD:-}"
    if [ -z "$password" ]; then
        password=$(openssl rand -base64 24)
    fi

    local secret_file="$TMP_DIR/argocd-redis-secret.yaml"
    cat > "$secret_file" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: argocd-redis
  namespace: argocd
  labels:
    app.kubernetes.io/managed-by: kubeseal
    app.kubernetes.io/component: argocd
type: Opaque
stringData:
  auth: ${password}
EOF

    seal_secret_file "$secret_file" "${SECRETS_DIR}/argocd-redis-sealed.yaml"
}

# --- grafana-cloud (credenciales de Grafana Cloud para Alloy/k8s-monitoring) -
generate_grafana_cloud() {
    echo "🔐 [grafana-cloud] Generating Grafana Cloud credentials secret (ns=monitoring)..."

    if [ -z "${GRAFANA_CLOUD_PROM_USER:-}" ] || [ -z "${GRAFANA_CLOUD_LOKI_USER:-}" ] || [ -z "${GRAFANA_CLOUD_TOKEN:-}" ]; then
        echo "❌ Faltan GRAFANA_CLOUD_PROM_USER / GRAFANA_CLOUD_LOKI_USER / GRAFANA_CLOUD_TOKEN (ponlos en .env.local)."
        echo "   Los IDs numéricos y el token salen de Grafana Cloud → Stack → Details."
        exit 1
    fi

    local secret_file="$TMP_DIR/grafana-cloud-credentials-secret.yaml"
    cat > "$secret_file" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: grafana-cloud-credentials
  namespace: monitoring
  labels:
    app.kubernetes.io/managed-by: kubeseal
    app.kubernetes.io/component: monitoring
type: Opaque
stringData:
  prometheus-username: "${GRAFANA_CLOUD_PROM_USER}"
  loki-username: "${GRAFANA_CLOUD_LOKI_USER}"
  access-token: ${GRAFANA_CLOUD_TOKEN}
EOF

    seal_secret_file "$secret_file" "${SECRETS_DIR}/grafana-cloud-credentials-sealed.yaml"
}

# --- velero (credenciales S3 de Cloudflare R2 para backups) ------------------
generate_velero() {
    echo "🔐 [velero] Generating Velero R2 credentials secret (ns=velero)..."

    if [ -z "${R2_ACCESS_KEY_ID:-}" ] || [ -z "${R2_SECRET_ACCESS_KEY:-}" ]; then
        echo "❌ Faltan R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY (ponlos en .env.local)."
        echo "   Se crean en Cloudflare → R2 → Manage API Tokens (scoped al bucket de backups)."
        exit 1
    fi

    local secret_file="$TMP_DIR/velero-r2-credentials-secret.yaml"
    cat > "$secret_file" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: velero-r2-credentials
  namespace: velero
  labels:
    app.kubernetes.io/managed-by: kubeseal
    app.kubernetes.io/component: velero
type: Opaque
stringData:
  cloud: |
    [default]
    aws_access_key_id=${R2_ACCESS_KEY_ID}
    aws_secret_access_key=${R2_SECRET_ACCESS_KEY}
EOF

    seal_secret_file "$secret_file" "${SECRETS_DIR}/velero-r2-credentials-sealed.yaml"
}

# --- cloudflare (token DNS-01 para cert-manager) ----------------------------
generate_cloudflare() {
    echo "🔐 [cloudflare] Generating Cloudflare API token secret (ns=cert-manager)..."

    if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
        echo "❌ CLOUDFLARE_API_TOKEN no está definido (ponlo en .env.local)."
        exit 1
    fi

    local secret_file="$TMP_DIR/cloudflare-api-token-secret.yaml"
    cat > "$secret_file" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token
  namespace: cert-manager
  labels:
    app.kubernetes.io/managed-by: kubeseal
    app.kubernetes.io/component: cert-manager
type: Opaque
stringData:
  api-token: ${CLOUDFLARE_API_TOKEN}
EOF

    seal_secret_file "$secret_file" "${SECRETS_DIR}/cloudflare-api-token-sealed.yaml"
}

show_instructions() {
    echo ""
    echo "📖 Next steps:"
    echo "1. Commit the sealed secret(s):"
    echo "   git add infra/bootstrap/secrets/*-sealed.yaml"
    echo "2. Apply to cluster (o deja que bootstrap-prod.sh / deploy-local.sh lo hagan):"
    echo "   kubectl apply -f infra/bootstrap/secrets/"
    echo ""
    echo "⚠️  Los SealedSecrets están ligados al cluster contra el que se sellaron."
}

main() {
    check_prerequisites
    setup_temp_dir

    case "$COMPONENT" in
        basic-auth)
            generate_basic_auth
            ;;
        grafana)
            generate_grafana
            ;;
        cloudflare)
            generate_cloudflare
            ;;
        argocd-redis)
            generate_argocd_redis
            ;;
        grafana-cloud)
            generate_grafana_cloud
            ;;
        velero)
            generate_velero
            ;;
        all)
            generate_basic_auth
            generate_grafana
            generate_cloudflare
            generate_argocd_redis
            # grafana-cloud NO va en 'all': requiere cuenta externa y sus
            # variables; se genera explícitamente (--component grafana-cloud)
            ;;
        *)
            echo "❌ Componente desconocido: $COMPONENT (basic-auth|grafana|cloudflare|argocd-redis|grafana-cloud|velero|all)"
            exit 1
            ;;
    esac

    show_instructions
    echo ""
    echo "🎉 Credential generation completed successfully!"
}

# Allow sourcing this script for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

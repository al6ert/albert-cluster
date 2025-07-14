#!/bin/bash
set -euo pipefail

# scripts/generate-credentials.sh - Generate secure credentials for basic auth
# Usage: ./scripts/generate-credentials.sh [--namespace NAMESPACE] [--users "user1,user2"]

# Source versions from centralized file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../versions.env"

# Default values (can be overridden)
NAMESPACE="${NAMESPACE:-admin}"
USERS="${USERS:-admin,argo}"
SECRET_NAME="${SECRET_NAME:-admin-basic-auth}"
BCRYPT_ROUNDS="${BCRYPT_ROUNDS:-12}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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
            echo "Usage: $0 [--namespace NAMESPACE] [--users \"user1,user2\"] [--secret-name NAME]"
            echo ""
            echo "Options:"
            echo "  --namespace    Target namespace (default: admin)"
            echo "  --users        Comma-separated users (default: admin,argo)"
            echo "  --secret-name  Secret name (default: admin-basic-auth)"
            echo ""
            echo "Environment variables:"
            echo "  NAMESPACE, USERS, SECRET_NAME, BCRYPT_ROUNDS"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "🔐 Generating secure credentials for basic authentication..."
echo "📋 Configuration:"
echo "   Namespace: $NAMESPACE"
echo "   Users: $USERS"
echo "   Secret name: $SECRET_NAME"
echo "   BCrypt rounds: $BCRYPT_ROUNDS"
echo ""

# Check prerequisites
check_prerequisites() {
    if ! command -v openssl >/dev/null 2>&1; then
        echo "❌ openssl not found. Please install openssl."
        exit 1
    fi

    if ! command -v htpasswd >/dev/null 2>&1; then
        echo "❌ htpasswd not found. Please install apache2-utils."
        exit 1
    fi

    if ! command -v kubeseal >/dev/null 2>&1; then
        echo "❌ kubeseal not found. Install it with:"
        echo "   curl -Lo kubeseal https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION#v}/kubeseal-linux-amd64"
        echo "   chmod +x kubeseal && sudo mv kubeseal /usr/local/bin/"
        exit 1
    fi
}

# Create secure temporary directory
setup_temp_dir() {
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT
    echo "📁 Using temporary directory: $TMP_DIR"
}

# Generate passwords and htpasswd file
generate_credentials() {
    echo "📝 Generating secure passwords..."

    # Create htpasswd file
    local htpasswd_file="$TMP_DIR/users.htpasswd"
    rm -f "$htpasswd_file"

    # Parse users and generate passwords
    IFS=',' read -ra USER_ARRAY <<< "$USERS"
    declare -A PASSWORDS

    for user in "${USER_ARRAY[@]}"; do
        user=$(echo "$user" | xargs)  # trim whitespace
        password=$(openssl rand -base64 20)
        PASSWORDS["$user"]="$password"

        echo "🔑 $user: $password"

        # Add to htpasswd file
        htpasswd -nbBC "$BCRYPT_ROUNDS" "$user" "$password" >> "$htpasswd_file"
    done

    echo "✅ Credentials generated"
    return 0
}

# Create Kubernetes Secret
create_k8s_secret() {
    echo "📦 Creating Kubernetes Secret..."

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
$(sed 's/^/    /' "$TMP_DIR/users.htpasswd")
EOF

    echo "✅ Secret created at $secret_file"
}

# Seal the secret
seal_secret() {
    echo "🔒 Sealing Secret with kubeseal..."

    local secret_file="$TMP_DIR/${SECRET_NAME}-secret.yaml"
    local sealed_file="${SCRIPT_DIR}/../infra/bootstrap/secrets/${SECRET_NAME}-sealed.yaml"

    # Ensure output directory exists
    mkdir -p "$(dirname "$sealed_file")"

    # Seal the secret
    kubeseal --format yaml < "$secret_file" > "$sealed_file"

    echo "✅ SealedSecret created at $sealed_file"
}

# Show usage instructions
show_instructions() {
    echo ""
    echo "📖 Next steps:"
    echo "1. Commit the sealed secret:"
    echo "   git add infra/bootstrap/secrets/${SECRET_NAME}-sealed.yaml"
    echo "   git commit -m 'feat: add sealed secret for basic auth'"
    echo ""
    echo "2. Apply to cluster:"
    echo "   kubectl apply -f infra/bootstrap/secrets/${SECRET_NAME}-sealed.yaml"
    echo ""
    echo "3. Verify unsealing:"
    echo "   kubectl get secret ${SECRET_NAME} -n ${NAMESPACE}"
    echo ""
    echo "🔐 Generated credentials (save these securely):"
    for user in "${USER_ARRAY[@]}"; do
        user=$(echo "$user" | xargs)
        echo "   $user: ${PASSWORDS[$user]}"
    done
}

main() {
    check_prerequisites
    setup_temp_dir
    generate_credentials
    create_k8s_secret
    seal_secret
    show_instructions

    echo ""
    echo "🎉 Credential generation completed successfully!"
}

# Allow sourcing this script for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
echo ""

# Limpiar archivos temporales
echo "🧹 Limpiando archivos temporales..."
rm -f tmp/admin-basic-auth-secret.yaml

echo "🎉 ¡Credenciales generadas exitosamente!"
echo ""
echo "📋 Resumen:"
echo "   - Archivo htpasswd: tmp/admin.htpasswd"
echo "   - SealedSecret: infra/bootstrap/secrets/admin-basic-auth-sealed.yaml"
echo "   - Usuarios: admin, argo"
echo ""
echo "⚠️  IMPORTANTE: Guarda las contraseñas en un lugar seguro:"
echo "   admin: $ADMIN_PASSWORD"
echo "   argo: $ARGO_PASSWORD"
echo ""
echo "🔧 Para regenerar credenciales, ejecuta este script nuevamente."

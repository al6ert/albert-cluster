#!/bin/bash

# Script para generar credenciales seguras para autenticación básica
# Uso: ./scripts/generate-credentials.sh

set -e

echo "🔐 Generando credenciales seguras para autenticación básica..."

# Crear directorio temporal si no existe
mkdir -p tmp

# Generar contraseñas seguras
echo "📝 Generando contraseñas seguras..."
ADMIN_PASSWORD=$(openssl rand -base64 20)
ARGO_PASSWORD=$(openssl rand -base64 20)

echo "🔑 Contraseñas generadas:"
echo "   admin: $ADMIN_PASSWORD"
echo "   argo: $ARGO_PASSWORD"
echo ""

# Generar archivo htpasswd con bcrypt (10 rondas)
echo "🔒 Generando archivo htpasswd con bcrypt..."
htpasswd -nbBC 10 admin "$ADMIN_PASSWORD" > tmp/admin.htpasswd
htpasswd -nbBC 10 argo "$ARGO_PASSWORD" >> tmp/admin.htpasswd

echo "✅ Archivo htpasswd generado en tmp/admin.htpasswd"
echo ""

# Crear Secret Kubernetes
echo "📦 Creando Secret Kubernetes..."
cat > tmp/admin-basic-auth-secret.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: admin-basic-auth
  namespace: admin
type: Opaque
stringData:
  users: |
$(cat tmp/admin.htpasswd | sed 's/^/    /')
EOF

echo "✅ Secret Kubernetes creado en tmp/admin-basic-auth-secret.yaml"
echo ""

# Sellar el Secret
echo "🔒 Sellando el Secret con kubeseal..."
kubeseal --format yaml < tmp/admin-basic-auth-secret.yaml > infra/bootstrap/secrets/admin-basic-auth-sealed.yaml

echo "✅ SealedSecret creado en infra/bootstrap/secrets/admin-basic-auth-sealed.yaml"
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
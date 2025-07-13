#!/bin/bash
set -euo pipefail

# Script wrapper para deploy local consistente con CI
# Ejecuta bootstrap (namespaces, CRDs, secrets) antes que apps

echo "🚀 Iniciando deploy local..."

# Cambiar al directorio del script
cd "$(dirname "$0")"

echo "📦 Aplicando bootstrap (namespaces, CRDs, secrets)..."
cd infra/bootstrap
kubectl apply -k .

# Esperar a que los CRDs estén establecidos
echo "⏳ Esperando CRDs establecidos..."
kubectl get crd -o name | grep -E 'cert-manager.io|traefik.io|acme.cert-manager.io|bitnami.com' | xargs kubectl wait --for=condition=Established --timeout=60s || echo "⚠️  Algunos CRDs no están listos, continuando..."

# Esperar unsealing de SealedSecrets (opcional para local)
echo "🔓 Esperando unsealing de SealedSecrets..."
for ss in $(kubectl get sealedsecrets -A -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || echo ""); do
  if [ -n "$ss" ]; then
    echo "  - Unsealing $ss..."
    kubectl wait sealedsecret/$ss -n admin --for=condition=Sealed=true --timeout=30s || echo "    ⚠️  Unsealing de $ss falló o timeout"
    secret_name=$ss
    kubectl wait secret/$secret_name -n admin --for=condition=Ready --timeout=30s || echo "    ⚠️  Secret $secret_name no ready"
  fi
done

echo "✅ Bootstrap completado"

echo "🚀 Desplegando aplicaciones..."
cd ../apps
helmfile --environment minikube apply

echo "✅ Deploy local completado!"
echo "🌐 Dashboard de Traefik: https://traefik.127.0.0.1.nip.io/dashboard/"
echo "🔐 Usuario: admin, Contraseña: admin" 
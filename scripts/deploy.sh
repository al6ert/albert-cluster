#!/bin/bash

# Script de deploy para diferentes entornos usando Kustomize
# Uso: ./scripts/deploy.sh [minikube|netcup]

set -e

ENVIRONMENT=${1:-minikube}

if [[ "$ENVIRONMENT" != "minikube" && "$ENVIRONMENT" != "netcup" ]]; then
    echo "❌ Entorno no válido. Uso: $0 [minikube|netcup]"
    exit 1
fi

echo "🚀 Iniciando deploy para entorno: $ENVIRONMENT"

# Función para aplicar aplicaciones de ArgoCD usando Kustomize
apply_argocd_apps() {
    local env=$1
    echo "📦 Aplicando aplicaciones de ArgoCD para $env usando Kustomize..."
    
    if [[ "$env" == "minikube" ]]; then
        kustomize build infra/apps/overlays/minikube | kubectl apply -f -
    else
        kubectl apply -k infra/apps/base/
    fi
}

# Función para verificar el estado de las aplicaciones
check_apps_status() {
    echo "🔍 Verificando estado de las aplicaciones..."
    kubectl get applications -n argocd
    
    echo "⏳ Esperando sincronización..."
    sleep 10
    
    # Verificar pods
    echo "📊 Estado de los pods:"
    kubectl get pods -A
}

# Función para mostrar información útil
show_info() {
    local env=$1
    echo ""
    echo "✅ Deploy completado para $env"
    echo ""
    
    if [[ "$env" == "minikube" ]]; then
        echo "🌐 URLs de acceso:"
        echo "  - Hello App: http://hello.127.0.0.1.nip.io"
        echo "  - Traefik Dashboard: http://traefik.127.0.0.1.nip.io"
        echo "  - ArgoCD: http://localhost:8080 (port-forward)"
        echo ""
        echo "🔧 Comandos útiles:"
        echo "  kubectl port-forward -n argocd svc/argocd-server 8080:80"
        echo "  kubectl get applications -n argocd"
        echo "  kubectl logs -n traefik -l app.kubernetes.io/name=traefik"
    else
        echo "🌐 URLs de acceso:"
        echo "  - Hello App: https://hello.albertperez.dev"
        echo "  - Traefik Dashboard: https://traefik.albertperez.dev"
        echo "  - ArgoCD: https://argocd.albertperez.dev"
        echo ""
        echo "🔧 Comandos útiles:"
        echo "  kubectl get applications -n argocd"
        echo "  kubectl logs -n traefik -l app.kubernetes.io/name=traefik"
    fi
}

# Función para limpiar aplicaciones anteriores
cleanup_old_apps() {
    echo "🧹 Limpiando aplicaciones anteriores..."
    
    # Eliminar todas las aplicaciones existentes
    kubectl delete application traefik -n argocd --ignore-not-found=true
    kubectl delete application hello -n argocd --ignore-not-found=true
    kubectl delete application argocd -n argocd --ignore-not-found=true
    
    sleep 5
}

# Verificar que ArgoCD esté funcionando
echo "🔍 Verificando ArgoCD..."
if ! kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server | grep -q Running; then
    echo "❌ ArgoCD no está funcionando. Por favor, instala ArgoCD primero."
    exit 1
fi

# Ejecutar deploy
cleanup_old_apps
apply_argocd_apps $ENVIRONMENT
check_apps_status
show_info $ENVIRONMENT

echo "🎉 Deploy completado exitosamente!" 
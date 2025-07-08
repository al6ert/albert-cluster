#!/bin/bash

# Script de deploy para diferentes entornos usando GitOps
# Uso: ./scripts/deploy.sh [minikube|netcup]

set -e

ENVIRONMENT=${1:-minikube}

if [[ "$ENVIRONMENT" != "minikube" && "$ENVIRONMENT" != "netcup" ]]; then
    echo "❌ Entorno no válido. Uso: $0 [minikube|netcup]"
    exit 1
fi

echo "🚀 Iniciando deploy GitOps para entorno: $ENVIRONMENT"

# Función para renderizar manifiestos
render_manifests() {
    local env=$1
    echo "📝 Renderizando manifiestos para $env..."
    
    # Verificar que helmfile esté instalado
    if ! command -v helmfile &> /dev/null; then
        echo "❌ helmfile no encontrado. Por favor, instálalo primero."
        exit 1
    fi
    
    # Crear directorio si no existe
    mkdir -p "infra/rendered/$env"
    
    # Renderizar manifiestos
    cd infra/apps
    helmfile --environment "$env" template > "../rendered/$env/all.yaml"
    cd ../..
    
    echo "✅ Manifiestos renderizados en infra/rendered/$env/all.yaml"
}

# Función para validar YAML
validate_yaml() {
    local env=$1
    echo "🔍 Validando sintaxis YAML..."
    
    if command -v python3 &> /dev/null; then
        python3 -c "import yaml; list(yaml.safe_load_all(open('infra/rendered/$env/all.yaml'))); print('✅ Sintaxis YAML válida')"
    else
        echo "⚠️  Python3 no encontrado, omitiendo validación YAML"
    fi
}

# Función para verificar el estado de ArgoCD
check_argocd_status() {
    echo "🔍 Verificando estado de ArgoCD..."
    
    if ! kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server | grep -q Running; then
        echo "❌ ArgoCD no está funcionando. Por favor, instala ArgoCD primero."
        exit 1
    fi
    
    echo "✅ ArgoCD está funcionando correctamente"
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
    echo "✅ Deploy GitOps completado para $env"
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
        echo ""
        echo "📝 Para ver el estado de sincronización:"
        echo "  kubectl get applications -n argocd -o wide"
        echo "  kubectl describe application cluster-minikube -n argocd"
    else
        echo "🌐 URLs de acceso:"
        echo "  - Hello App: https://hello.albertperez.dev"
        echo "  - Traefik Dashboard: https://traefik.albertperez.dev"
        echo "  - ArgoCD: https://argocd.albertperez.dev"
        echo ""
        echo "🔧 Comandos útiles:"
        echo "  kubectl get applications -n argocd"
        echo "  kubectl logs -n traefik -l app.kubernetes.io/name=traefik"
        echo ""
        echo "📝 Para ver el estado de sincronización:"
        echo "  kubectl get applications -n argocd -o wide"
        echo "  kubectl describe application cluster-root -n argocd"
    fi
}

# Función para forzar sincronización (opcional)
force_sync() {
    local env=$1
    echo "🔄 Forzando sincronización de ArgoCD..."
    
    if [[ "$env" == "minikube" ]]; then
        kubectl patch application cluster-minikube -n argocd --type='merge' -p='{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
    else
        kubectl patch application cluster-root -n argocd --type='merge' -p='{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
    fi
    
    echo "✅ Sincronización forzada"
}

# Ejecutar deploy GitOps
check_argocd_status
render_manifests $ENVIRONMENT
validate_yaml $ENVIRONMENT

echo ""
echo "🎯 Manifiestos renderizados y validados."
echo "📤 ArgoCD detectará automáticamente los cambios y sincronizará."
echo ""

# Preguntar si quiere forzar sincronización
read -p "¿Deseas forzar la sincronización de ArgoCD? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    force_sync $ENVIRONMENT
fi

check_apps_status
show_info $ENVIRONMENT

echo "🎉 Deploy GitOps completado exitosamente!" 
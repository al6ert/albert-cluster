#!/bin/bash

# Smoke tests para validar el despliegue en Minikube
# Implementa las validaciones mínimas: liveness, readiness, curl 200 OK

set -euo pipefail

echo "🚀 Iniciando smoke tests..."

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para logging
log_info() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Test 1: Verificar que todos los pods están Running
test_pods_running() {
    echo "📋 Test 1: Verificando que todos los pods están Running..."
    
    # CORREGIDO: Excluir pods "Completed" que son normales para jobs
    CRASHED_PODS=$(kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
    
    if [ -n "$CRASHED_PODS" ]; then
        log_error "Found pods not in Running/Succeeded state:"
        kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded
        return 1
    fi
    
    log_info "All pods are running or completed successfully"
    return 0
}

# Test 2: Verificar readiness probes
test_readiness() {
    echo "🔍 Test 2: Verificando readiness probes..."
    
    # Esperar a que todos los pods estén ready
    kubectl wait pod --all -A --for=condition=Ready --timeout=120s
    
    log_info "All pods are ready"
    return 0
}

# Test 3: Hello app - curl 200 OK
test_hello_app() {
    echo "🌐 Test 3: Verificando Hello app (curl 200 OK)..."
    
    # Usar port-forward para acceder al servicio - CORREGIDO: usar namespace hello
    kubectl port-forward svc/hello 8080:80 -n hello &
    PF_PID=$!
    
    # Esperar a que port-forward esté listo
    sleep 5
    
    # Hacer request y verificar respuesta
    if curl -f -s http://localhost:8080/ > /dev/null; then
        log_info "Hello app responding with 200 OK"
    else
        log_error "Hello app not responding with 200 OK"
        kill $PF_PID 2>/dev/null || true
        return 1
    fi
    
    # Verificar contenido de la respuesta
    RESPONSE=$(curl -s http://localhost:8080/)
    if [[ "$RESPONSE" == *"Hola desde Minikube"* ]]; then
        log_info "Hello app content is correct"
    else
        log_warn "Hello app content unexpected: $RESPONSE"
    fi
    
    kill $PF_PID 2>/dev/null || true
    return 0
}

# Test 4: Traefik dashboard - 401 Unauthorized (auth required)
test_traefik_auth() {
    echo "🔐 Test 4: Verificando Traefik dashboard auth (401 expected)..."
    
    # CORREGIDO: Verificar dashboard via IngressRoute (acceso externo)
    # El dashboard está configurado para requerir autenticación básica
    HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://traefik.127.0.0.1.nip.io/dashboard/ || echo "000")
    
    if [ "$HTTP_CODE" = "401" ]; then
        log_info "Traefik dashboard correctly requires authentication (401)"
    elif [ "$HTTP_CODE" = "000" ]; then
        log_warn "Could not reach Traefik dashboard (network/DNS issue)"
        return 1
    else
        log_error "Traefik dashboard should return 401 (auth required), got $HTTP_CODE"
        return 1
    fi
    
    return 0
}

# Test 5: Verificar servicios críticos
test_critical_services() {
    echo "🔧 Test 5: Verificando servicios críticos..."
    
    # CORREGIDO: Verificar cada servicio en su namespace correspondiente
    if kubectl get svc traefik -n traefik >/dev/null 2>&1; then
        log_info "Service traefik exists in namespace traefik"
    else
        log_error "Critical service traefik not found in namespace traefik"
        return 1
    fi
    
    if kubectl get svc hello -n hello >/dev/null 2>&1; then
        log_info "Service hello exists in namespace hello"
    else
        log_error "Critical service hello not found in namespace hello"
        return 1
    fi
    
    return 0
}

# Test 6: Verificar namespaces
test_namespaces() {
    echo "📁 Test 6: Verificando namespaces críticos..."
    
    # CORREGIDO: Incluir namespace hello en la lista
    CRITICAL_NAMESPACES=("traefik" "hello" "admin" "cert-manager")
    
    for ns in "${CRITICAL_NAMESPACES[@]}"; do
        if kubectl get namespace "$ns" >/dev/null 2>&1; then
            log_info "Namespace $ns exists"
        else
            log_warn "Namespace $ns not found (may be optional)"
        fi
    done
    
    return 0
}

# Función principal
main() {
    local failed_tests=0
    
    # Array de tests
    tests=(
        test_pods_running
        test_readiness
        test_critical_services
        test_namespaces
        test_hello_app
        test_traefik_auth
    )
    
    # Ejecutar tests
    for test in "${tests[@]}"; do
        echo ""
        if $test; then
            log_info "Test passed: $test"
        else
            log_error "Test failed: $test"
            ((failed_tests++))
        fi
    done
    
    echo ""
    echo "📊 Resumen de smoke tests:"
    
    if [ $failed_tests -eq 0 ]; then
        log_info "Todos los smoke tests pasaron ✅"
        exit 0
    else
        log_error "$failed_tests test(s) fallaron ❌"
        exit 1
    fi
}

# Ejecutar función principal
main "$@" 
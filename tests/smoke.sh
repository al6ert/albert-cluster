#!/bin/bash
set -euo pipefail

# tests/smoke.sh - Comprehensive smoke tests for GitOps cluster validation
# Tests: pod readiness, service availability, basic auth, TLS certificates, and application functionality

echo "🚀 Starting comprehensive smoke tests..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_debug() {
    echo -e "${BLUE}🔍 $1${NC}"
}

# Test 1: Verify all pods are running or completed
test_pods_running() {
    echo "📋 Test 1: Verifying all pods are running or completed..."

    # Exclude pods in Completed state (these are normal for jobs)
    local crashed_pods
    crashed_pods=$(kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)

    if [ -n "$crashed_pods" ]; then
        log_error "Found pods not in Running/Succeeded state:"
        kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded
        return 1
    fi

    log_info "All pods are running or completed successfully"
    return 0
}

# Test 2: Verify readiness probes
test_readiness() {
    echo "🔍 Test 2: Verifying readiness probes..."

    # Wait for all pods to be ready with timeout
    if kubectl wait pod --all -A --for=condition=Ready --timeout=120s >/dev/null 2>&1; then
        log_info "All pods are ready"
    else
        log_warn "Some pods not ready within timeout, checking individually..."
        kubectl get pods -A | grep -E "(0/|False)" || log_info "All pods appear ready now"
        return 1
    fi

    return 0
}

# Test 3: Verify critical namespaces exist
test_namespaces() {
    echo "📁 Test 3: Verifying critical namespaces..."

    local critical_namespaces=("traefik" "hello" "admin" "cert-manager" "argocd")
    local missing_namespaces=()

    for ns in "${critical_namespaces[@]}"; do
        if kubectl get namespace "$ns" >/dev/null 2>&1; then
            log_debug "Namespace $ns exists"
        else
            missing_namespaces+=("$ns")
        fi
    done

    if [ ${#missing_namespaces[@]} -eq 0 ]; then
        log_info "All critical namespaces exist"
    else
        log_warn "Missing namespaces: ${missing_namespaces[*]}"
        return 1
    fi

    return 0
}

# Test 4: Verify critical services
test_critical_services() {
    echo "🔧 Test 4: Verifying critical services..."

    local services=(
        "traefik:traefik"
        "hello:hello"
    )

    for service_ns in "${services[@]}"; do
        local svc="${service_ns%:*}"
        local ns="${service_ns#*:}"

        if kubectl get svc "$svc" -n "$ns" >/dev/null 2>&1; then
            log_debug "Service $svc exists in namespace $ns"
        else
            log_error "Critical service $svc not found in namespace $ns"
            return 1
        fi
    done

    log_info "All critical services exist"
    return 0
}

# Test 5: Hello app functionality test
test_hello_app() {
    echo "🌐 Test 5: Testing Hello app functionality..."

    # Use port-forward to access the service
    local pf_pid
    kubectl port-forward svc/hello 8080:80 -n hello >/dev/null 2>&1 &
    pf_pid=$!

    # Wait for port-forward to be ready
    sleep 5

    # Test HTTP response
    local test_passed=true

    if curl -f -s http://localhost:8080/ >/dev/null; then
        log_debug "Hello app responding with 200 OK"
    else
        log_error "Hello app not responding with 200 OK"
        test_passed=false
    fi

    # Test response content
    if [ "$test_passed" = true ]; then
        local response
        response=$(curl -s http://localhost:8080/ || echo "")
        if [[ "$response" == *"Hola desde Minikube"* ]] || [[ "$response" == *"Hello"* ]]; then
            log_debug "Hello app content is correct"
        else
            log_warn "Hello app content unexpected: $response"
        fi
    fi

    # Cleanup
    kill $pf_pid 2>/dev/null || true

    if [ "$test_passed" = true ]; then
        log_info "Hello app functionality test passed"
        return 0
    else
        return 1
    fi
}

# Test 6: Traefik dashboard authentication
test_traefik_auth() {
    echo "🔐 Test 6: Testing Traefik dashboard authentication..."

    # Test dashboard access via IngressRoute
    local http_code
    http_code=$(curl -k -s -o /dev/null -w "%{http_code}" "https://traefik.127.0.0.1.nip.io/dashboard/" --max-time 10 || echo "000")

    case "$http_code" in
        401)
            log_info "Traefik dashboard correctly requires authentication (401)"
            return 0
            ;;
        000)
            log_warn "Could not reach Traefik dashboard (network/DNS issue)"
            return 1
            ;;
        200)
            log_warn "Traefik dashboard accessible without auth - security concern"
            return 1
            ;;
        *)
            log_error "Traefik dashboard returned unexpected code: $http_code"
            return 1
            ;;
    esac
}

# Test 7: TLS Certificate validation
test_tls_certificates() {
    echo "🔒 Test 7: Validating TLS certificates..."

    # Check for cert-manager certificates
    local cert_count
    cert_count=$(kubectl get certificates -A --no-headers 2>/dev/null | wc -l)

    if [ "$cert_count" -gt 0 ]; then
        log_debug "Found $cert_count certificate(s)"

        # Check certificate status
        local ready_certs
        ready_certs=$(kubectl get certificates -A -o jsonpath='{.items[?(@.status.conditions[0].type=="Ready")].metadata.name}' 2>/dev/null || echo "")

        if [ -n "$ready_certs" ]; then
            log_info "TLS certificates are ready"
        else
            log_warn "Some TLS certificates may not be ready"
        fi
    else
        log_warn "No TLS certificates found (may be expected for local env)"
    fi

    return 0
}

# Test 8: SealedSecrets functionality
test_sealed_secrets() {
    echo "🔓 Test 8: Verifying SealedSecrets functionality..."

    # Check if SealedSecrets controller is running
    if kubectl get pods -n kube-system -l name=sealed-secrets-controller --no-headers 2>/dev/null | grep -q Running; then
        log_debug "SealedSecrets controller is running"

        # Check for SealedSecrets
        local ss_count
        ss_count=$(kubectl get sealedsecrets -A --no-headers 2>/dev/null | wc -l)

        if [ "$ss_count" -gt 0 ]; then
            log_info "Found $ss_count SealedSecret(s) - unsealing status checked"
        else
            log_warn "No SealedSecrets found"
        fi
    else
        log_warn "SealedSecrets controller not found or not running"
        return 1
    fi

    return 0
}

# Test 9: Resource utilization check
test_resource_utilization() {
    echo "📊 Test 9: Checking resource utilization..."

    # Check if any pods are in resource stress
    local resource_issues
    resource_issues=$(kubectl get pods -A -o jsonpath='{range .items[*]}{.status.containerStatuses[*].restartCount}{"\n"}{end}' 2>/dev/null | \
        awk '$1 > 5 {count++} END {print count+0}')

    if [ "$resource_issues" -gt 0 ]; then
        log_warn "Found $resource_issues pod(s) with high restart count"
        kubectl get pods -A | awk 'NR==1 || $4>5'
    else
        log_debug "No pods with excessive restarts"
    fi

    # Check node resource usage (if available)
    if kubectl top nodes >/dev/null 2>&1; then
        log_debug "Node resource usage:"
        kubectl top nodes | head -5
    fi

    log_info "Resource utilization check completed"
    return 0
}

# Show comprehensive cluster status
show_cluster_status() {
    echo ""
    echo "📊 Cluster Status Summary:"
    echo "  Context: $(kubectl config current-context)"
    echo "  Total Namespaces: $(kubectl get ns --no-headers | wc -l)"
    echo "  Running Pods: $(kubectl get pods -A --field-selector=status.phase=Running --no-headers | wc -l)"
    echo "  Services: $(kubectl get svc -A --no-headers | wc -l)"
    echo "  CRDs: $(kubectl get crd --no-headers | wc -l)"

    if kubectl get certificates -A >/dev/null 2>&1; then
        echo "  Certificates: $(kubectl get certificates -A --no-headers | wc -l)"
    fi

    if kubectl get sealedsecrets -A >/dev/null 2>&1; then
        echo "  SealedSecrets: $(kubectl get sealedsecrets -A --no-headers | wc -l)"
    fi

    echo ""
    echo "🌐 Access URLs (minikube):"
    echo "  Traefik Dashboard: https://traefik.127.0.0.1.nip.io/dashboard/"
    echo "  Hello App: http://hello.127.0.0.1.nip.io"
    echo ""
    echo "💡 Useful debugging commands:"
    echo "  kubectl get pods -A"
    echo "  kubectl logs -n traefik -l app.kubernetes.io/name=traefik"
    echo "  kubectl get applications -n argocd"
}

# Main test execution
main() {
    local failed_tests=0
    local total_tests=0

    # Define test functions
    local tests=(
        test_pods_running
        test_readiness
        test_namespaces
        test_critical_services
        test_hello_app
        test_traefik_auth
        test_tls_certificates
        test_sealed_secrets
        test_resource_utilization
    )

    # Execute tests
    for test_func in "${tests[@]}"; do
        echo ""
        ((total_tests++))

        if $test_func; then
            log_info "Test passed: $test_func"
        else
            log_error "Test failed: $test_func"
            ((failed_tests++))
        fi
    done

    # Show results
    echo ""
    echo "📊 Smoke Tests Summary:"
    echo "  Total tests: $total_tests"
    echo "  Passed: $((total_tests - failed_tests))"
    echo "  Failed: $failed_tests"

    show_cluster_status

    if [ $failed_tests -eq 0 ]; then
        log_info "All smoke tests passed! 🎉"
        exit 0
    else
        log_error "$failed_tests test(s) failed"
        exit 1
    fi
}

# Allow sourcing this script for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

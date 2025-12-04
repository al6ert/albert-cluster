#!/bin/bash
#
# Comprehensive smoke tests for GitOps cluster validation
#   • Pod readiness, service availability, basic auth, TLS certificates, application checks
#   • Adapted for CI runners: longer timeouts & smarter waits
#

set -euo pipefail

# ---------- Config ----------
WAIT_TIMEOUT=${WAIT_TIMEOUT:-5s}   # Tiempo máximo para que los pods estén Ready
# -----------------------------

echo "🚀 Starting comprehensive smoke tests..."

# Colores para la salida
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log_info()  { echo -e "${GREEN}✅ $1${NC}"; }
log_warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_debug() { echo -e "${BLUE}🔍 $1${NC}"; }


# ---------- Port Forwarding Setup ----------
PF_PID=""
setup_port_forward() {
  echo "🔌 Setting up port-forward to Traefik..."
  # Kill any existing port-forward on 8443 just in case
  lsof -ti:8443 | xargs kill -9 2>/dev/null || true

  kubectl port-forward -n traefik svc/traefik 8443:443 >/dev/null 2>&1 &
  PF_PID=$!

  # Wait for port to be open
  local retries=10
  while ! nc -z 127.0.0.1 8443 && [ $retries -gt 0 ]; do
    sleep 1
    ((retries--))
  done

  if [ $retries -eq 0 ]; then
    log_error "Failed to establish port-forward to Traefik"
    return 1
  fi
  log_info "Port-forward established on 127.0.0.1:8443"
}

cleanup() {
  if [ -n "$PF_PID" ]; then
    echo "🧹 Cleaning up port-forward..."
    kill $PF_PID 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ---------- Tests ----------

# Test 1 – Todos los pods Running/Succeeded
test_pods_running() {
  echo "📋 Test 1: Verifying all pods are running or completed..."
  local crashed_pods
  crashed_pods=$(kubectl get pods --all-namespaces \
       --field-selector=status.phase!=Running,status.phase!=Succeeded \
       -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[*].state.waiting.reason}{"\n"}{end}' 2>/dev/null | \
       grep -v "PodInitializing" | awk '{print $1}' || true)

  if [ -n "$crashed_pods" ]; then
    log_error "Found pods not in Running/Succeeded state:"
    kubectl get pods --all-namespaces \
      --field-selector=status.phase!=Running,status.phase!=Succeeded
    return 1
  fi
  log_info "All pods are running or completed successfully"
  return 0
}

# Test 2 – Readiness probes con exclusión de Jobs completados/erróneos
test_readiness() {
  echo "🔍 Test 2: Verifying readiness probes..."
  if kubectl wait pod --all -A \
        --for=condition=Ready \
        --field-selector=status.phase!=Succeeded,status.phase!=Failed \
        --timeout="$WAIT_TIMEOUT" >/dev/null 2>&1; then
    log_info "All pods are ready"
  else
    log_warn "Some pods not ready within timeout, checking individually..."
    kubectl get pods -A | grep -E "(0/|False)" || log_info "All pods appear ready now"
    return 1
  fi
  return 0
}

# Test 3 – Comprobación de *namespaces* críticos
test_namespaces() {
  echo "📁 Test 3: Verifying critical namespaces..."
  local critical_namespaces=(traefik hello admin cert-manager argocd) missing=()
  for ns in "${critical_namespaces[@]}"; do
    if kubectl get namespace "$ns" >/dev/null 2>&1; then
      log_debug "Namespace $ns exists"
    else
      missing+=("$ns")
    fi
  done
  if [ ${#missing[@]} -eq 0 ]; then
    log_info "All critical namespaces exist"
  else
    log_warn "Missing namespaces: ${missing[*]}"
    return 1
  fi
  return 0
}

# Test 4 – Servicios críticos
test_critical_services() {
  echo "🔧 Test 4: Verifying critical services..."
  local services=( "traefik:traefik" "hello:hello" )
  for pair in "${services[@]}"; do
    local svc="${pair%:*}" ns="${pair#*:}"
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

# Test 5 – Funcionalidad de la Hello app
test_hello_app() {
  echo "🌐 Test 5: Testing Hello app functionality (HTTPS via Ingress)..."

  local host_ip="127.0.0.1"
  local url="https://hello.127.0.0.1.nip.io:8443/"

  local ok=false
  for i in {1..3}; do
    # Use -k because it's a self-signed cert (or CA might not be trusted by curl in runner)
    # Target port 8443 via localhost
    if curl -k -f -s --resolve "hello.127.0.0.1.nip.io:8443:$host_ip" "$url" >/dev/null; then
      ok=true; break
    fi
    log_warn "Retry $i: Hello app not reachable via Ingress (port 8443), sleeping 10s..."
    sleep 10
  done

  if $ok; then
    local resp
    resp=$(curl -k -s --resolve "hello.127.0.0.1.nip.io:8443:$host_ip" "$url" || echo "")
    [[ "$resp" =~ (Hola\ desde\ Minikube|Hello) ]] \
      && log_debug "Hello app content is correct" \
      || log_warn "Hello app content unexpected: $resp"
    log_info "Hello app functionality test passed"
    return 0
  else
    log_error "Hello app not responding via Ingress after retries"
    return 1
  fi
}

# Test 6 – Autenticación del dashboard Traefik
# Test 6 – Autenticación del dashboard Traefik
test_traefik_auth() {
  echo "🔐 Test 6: Testing Traefik dashboard authentication..."

  local dashboard_url code

  # 1) Intento HTTPS usando port-forward (puerto 8443)
  local host_ip="127.0.0.1"

  # Usamos --resolve para forzar la resolución del dominio a localhost
  dashboard_url="https://traefik.127.0.0.1.nip.io:8443/dashboard/"
  for i in {1..3}; do
    code=$(curl -k -s -o /dev/null -w "%{http_code}" \
           --resolve "traefik.127.0.0.1.nip.io:8443:$host_ip" \
           "$dashboard_url" --max-time 20 || echo 000)
    [ "$code" != 000 ] && break
    log_warn "Retry $i: HTTPS not reachable on port 8443, sleeping 10 s…"; sleep 10
  done

  # 2) Fallback HTTP si HTTPS no responde
  if [ "$code" = 000 ]; then
    dashboard_url="http://traefik.127.0.0.1.nip.io/dashboard/"
    for i in {1..3}; do
      code=$(curl -s -o /dev/null -w "%{http_code}" \
             "$dashboard_url" --max-time 20 || echo 000)
      [ "$code" != 000 ] && break
      log_warn "Retry $i: HTTP not reachable, sleeping 10 s…"; sleep 10
    done
  fi

  # 3) Último recurso: port‑forward al puerto 9000
  if [ "$code" = 000 ]; then
    kubectl port-forward -n traefik deployment/traefik \
      9000:9000 >/dev/null 2>&1 &
    local pf_pid=$!
    sleep 5
    dashboard_url="http://localhost:9000/dashboard/"
    code=$(curl -s -o /dev/null -w "%{http_code}" \
           "$dashboard_url" --max-time 20 || echo 000)
    kill $pf_pid 2>/dev/null || true
  fi

  case "$code" in
    401|302)
      log_info "Traefik dashboard reachable & requires auth ($code)";;
    000)
      log_error "Traefik dashboard unreachable after all fallbacks"; return 1;;
    *)
      log_warn "Traefik dashboard returned unexpected code: $code"; return 1;;
  esac
  return 0
}

# Test 7 – Certificados TLS
test_tls_certificates() {
  echo "🔒 Test 7: Validating TLS certificates..."
  local total ready
  total=$(kubectl get certificates -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
  ready=$(kubectl get certificates -A \
          -o jsonpath='{.items[?(@.status.conditions[0].type=="Ready")].metadata.name}' 2>/dev/null || echo "")
  if [ "$total" -gt 0 ]; then
    log_debug "Certificates found: $total"
    [ -n "$ready" ] \
      && log_info "TLS certificates are ready" \
      || log_warn "Some TLS certificates may not be ready"
  else
    log_warn "No TLS certificates found (may be expected for local env)"
  fi
  return 0
}

# Test 8 – SealedSecrets
test_sealed_secrets() {
  echo "🔓 Test 8: Verifying SealedSecrets functionality..."

  # La etiqueta correcta es app.kubernetes.io/name=sealed-secrets
  if kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets \
         --no-headers 2>/dev/null | grep -q Running; then
    log_debug "SealedSecrets controller is running"
    local count
    count=$(kubectl get sealedsecrets -A --no-headers 2>/dev/null | wc -l)
    [ "$count" -gt 0 ] \
      && log_info "Found $count SealedSecret(s)" \
      || log_warn "No SealedSecrets found"
  else
    log_warn "SealedSecrets controller not found or not running"
    return 1
  fi
  return 0
}

# Test 9 – Uso de recursos
test_resource_utilization() {
  echo "📊 Test 9: Checking resource utilization..."
  local restarts
  restarts=$(kubectl get pods -A -o jsonpath='{range .items[*]}'\
'{.status.containerStatuses[*].restartCount}{"\n"}{end}' 2>/dev/null | \
             awk '$1 > 5 {c++} END {print c+0}')
  if [ "$restarts" -gt 0 ]; then
    log_warn "Found $restarts pod(s) with >5 restarts"
    kubectl get pods -A | awk 'NR==1 || $4>5'
  else
    log_debug "No pods with excessive restarts"
  fi
  if kubectl top nodes >/dev/null 2>&1; then
    log_debug "Node resource usage:"; kubectl top nodes | head -5
  fi
  log_info "Resource utilization check completed"
  return 0
}

# ---------- Resumen de estado ----------
show_cluster_status() {
  echo -e "\n📊 Cluster Status Summary:"
  echo "  Context: $(kubectl config current-context)"
  echo "  Total Namespaces: $(kubectl get ns --no-headers | wc -l)"
  echo "  Running Pods: $(kubectl get pods -A \
                       --field-selector=status.phase=Running --no-headers | wc -l)"
  echo "  Services: $(kubectl get svc -A --no-headers | wc -l)"
  echo "  CRDs: $(kubectl get crd --no-headers | wc -l)"
  kubectl get certificates -A >/dev/null 2>&1 \
    && echo "  Certificates: $(kubectl get certificates -A --no-headers | wc -l)"
  kubectl get sealedsecrets -A >/dev/null 2>&1 \
    && echo "  SealedSecrets: $(kubectl get sealedsecrets -A --no-headers | wc -l)"
  echo -e "\n🌐 Access URLs (minikube):"
  echo "  Traefik Dashboard: https://traefik.127.0.0.1.nip.io/dashboard/"
  echo "  Hello App:        http://hello.127.0.0.1.nip.io"
}

# ---------- Ejecución principal ----------
main() {
  local failed=0 total=0

  # Start port-forwarding before tests
  setup_port_forward || return 1

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

  # Permite continuar para mostrar el resumen aunque falle una prueba
  set +e
  for t in "${tests[@]}"; do
    echo ""; ((total++))
    if $t; then
      log_info "Test passed: $t"
    else
      log_error "Test failed: $t"; ((failed++))
      # Diagnóstico rápido
      kubectl get pods -A -o wide
    fi
  done
  set -e

  echo -e "\n📊 Smoke Tests Summary:"
  echo "  Total tests: $total"
  echo "  Passed: $((total - failed))"
  echo "  Failed: $failed"

  show_cluster_status
  [ "$failed" -eq 0 ] && log_info "All smoke tests passed! 🎉" || log_error "$failed test(s) failed"
  return "$failed"
}

# Ejecutar si es la entrada principal
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"

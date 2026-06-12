# Albert Cluster - Canonical GitOps with Helmfile + ArgoCD

A production-ready GitOps cluster implementation using ArgoCD and Helmfile, following DRY principles, idempotent operations, and security best practices.

## 🏗️ Architecture Overview

This project implements a **pure GitOps** approach where:
- **ArgoCD** manages cluster state from Git repository
- **Helmfile** renders application manifests with environment-specific values
- **Sealed Secrets** manages sensitive data securely
- **Cert-manager** provides TLS certificates (self-signed for dev, Let's Encrypt for prod)
- **Traefik + Gateway API** expose applications: a shared `Gateway` (traefik-gateway)
  terminates TLS with the per-environment wildcard certificate and apps attach
  `HTTPRoute`s to it. The Traefik dashboard keeps a native `IngressRoute`
  (api@internal) and the ArgoCD gRPC API keeps a classic `Ingress` (h2c).

## 📁 Project Structure

```
albert-cluster/
├── versions.env                      # 🔧 Centralized version management
├── .yamllint.yml                     # 📝 YAML linting configuration
├── deploy-local.sh                   # 🚀 Idempotent local deployment script
├── .github/
│   ├── actions/                      # 🔄 Reusable composite actions
│   │   ├── setup-tools/             # Tool installation (Helm, Helmfile, kubectl, yq)
│   │   └── validate-manifests/      # YAML validation and linting
│   └── workflows/
│       ├── ci.yaml                  # 🌟 Main CI/CD pipeline (DRY)
│       └── dev-ci-enhanced.yaml     # 🔬 Enhanced dev workflow
├── infra/
│   ├── bootstrap/                   # 🏗️ Bootstrap resources (CRDs, namespaces, secrets)
│   │   ├── kustomization.yaml       # Ordered bootstrap application
│   │   ├── namespaces/              # Namespace definitions with sync waves
│   │   ├── crds/                    # Custom Resource Definitions
│   │   ├── secrets/                 # SealedSecrets for sensitive data
│   │   ├── middlewares/             # Traefik middleware definitions
│   │   ├── rbac/                    # RBAC for GitHub Actions
│   │   ├── argocd-root.yaml         # 🎯 ArgoCD app for production (pure GitOps)
│   │   └── argocd-minikube.yaml     # 🎯 ArgoCD app for development (pure GitOps)
│   ├── apps/                        # 📦 Application definitions
│   │   ├── helmfile.yaml            # Root Helmfile with environment configurations
│   │   ├── cert-manager/            # Certificate management
│   │   ├── sealed-secrets/          # Secret encryption controller
│   │   ├── traefik/                 # Ingress controller with auth
│   │   └── hello/                   # Sample application
│   ├── envs/                        # 🌍 Environment-specific configurations
│   │   ├── minikube/               # Local development values
│   │   │   ├── global-values.yaml  # Global environment configuration
│   │   │   ├── traefik-values.yaml # Traefik overrides for minikube
│   │   │   ├── cert-manager-values.yaml
│   │   │   └── hello-values.yaml
│   │   └── netcup/                 # Production values
│   │       ├── global-values.yaml  # Global production configuration
│   │       ├── traefik-values.yaml # Traefik overrides for production
│   │       ├── cert-manager-values.yaml
│   │       └── hello-values.yaml
│   └── charts/                      # 📊 Local Helm charts
│       └── hello/                   # Custom hello world application
├── scripts/
│   ├── deploy.sh                    # 🎯 Idempotent GitOps deployment
│   └── generate-credentials.sh     # 🔐 Secure credential generation
└── tests/
    └── smoke.sh                     # 🧪 Comprehensive smoke tests
```

## ✨ Key Features & Improvements

### 🔧 Centralized Version Management
- **`versions.env`**: Single source of truth for all tool and chart versions
- Used across workflows, scripts, and Helmfile templates
- Eliminates version drift and simplifies updates

### 🎯 Pure GitOps Workflow
- **No rendered manifests in Git**: ArgoCD uses direct repo paths with Helmfile plugin
- **Environment variables**: Chart versions injected into ArgoCD applications
- **Sync waves**: Proper ordering with annotations for resource dependencies

### 🔄 DRY Principles Applied
- **Composite Actions**: Reusable GitHub Actions for setup and validation
- **Global Values**: Consistent use of `network.domain` and `environment.name`
- **Template Inheritance**: Environment values override base configurations

### 🛡️ Security & Best Practices
- **SealedSecrets**: All sensitive data encrypted at rest
- **RBAC**: Minimal GitHub Actions permissions
- **BCrypt**: Strong password hashing for basic auth
- **TLS**: Automated certificate management

### 🔍 Enhanced Validation
- **YAMLlint**: Consistent YAML formatting and syntax checking
- **Helmfile lint**: Helm template validation
- **Smoke tests**: Comprehensive functionality testing
- **Namespace consistency**: Verification across environments

## 🚀 Quick Start

### Prerequisites

Ensure you have these tools installed:
```bash
# Source centralized versions
source versions.env

# Install required tools
curl -Lo helmfile https://github.com/helmfile/helmfile/releases/download/${HELMFILE_VERSION}/helmfile_linux_amd64
curl -Lo kubeseal https://github.com/bitnami-labs/sealed-secrets/releases/download/${KUBESEAL_VERSION}/kubeseal-linux-amd64
```

### Local Development Setup

1. **Start Minikube**:
```bash
source versions.env
minikube start --driver=docker --kubernetes-version=${KUBERNETES_VERSION}
```

2. **Deploy cluster**:
```bash
# Idempotent local deployment
./deploy-local.sh

# Or use the GitOps script
./scripts/deploy.sh minikube
```

3. **Verify deployment**:
```bash
# Run comprehensive smoke tests
./tests/smoke.sh

# Check cluster status
kubectl get pods -A
kubectl get applications -n argocd
```

4. **Access applications**:
- **Traefik Dashboard**: https://traefik.127.0.0.1.nip.io/dashboard/
- **Hello App**: http://hello.127.0.0.1.nip.io
- **Default credentials**: admin / admin

### Production Deployment

1. **Configure secrets** (con el contexto kubectl apuntando al cluster de producción):
```bash
# Pon los valores reales en .env.local (no versionado):
#   ADMIN_PASSWORD, GRAFANA_ADMIN_PASSWORD, CLOUDFLARE_API_TOKEN
./scripts/generate-credentials.sh --component all
git add infra/bootstrap/secrets/*-sealed.yaml && git commit -m 'chore: rotate sealed secrets'
```

2. **Bootstrap production**:
```bash
./scripts/bootstrap-prod.sh
```

## 🌍 Environment Configuration

### Minikube (Development)
- **Domain**: `127.0.0.1.nip.io`
- **TLS**: Self-signed certificates via local CA
- **Resources**: Limited CPU/memory
- **Replicas**: Single replica for most services

### Netcup (Production)
- **Domain**: `albertperez.dev`
- **TLS**: Let's Encrypt certificates via DNS01 challenge
- **Resources**: Full production allocation
- **Replicas**: Multiple replicas for HA

## 🔐 Security

### Gestión de secretos (un único mecanismo: SealedSecrets)

Todas las credenciales del cluster viven como `SealedSecret` y se generan con
**un único script**, `scripts/generate-credentials.sh`:

| Componente   | Secret (namespace)                | Consumidor                                  |
|--------------|-----------------------------------|---------------------------------------------|
| `basic-auth` | `admin-basic-auth` (admin)        | Middleware basic-auth del dashboard Traefik |
| `grafana`    | `grafana-admin` (monitoring)      | `grafana.admin.existingSecret`              |
| `cloudflare` | `cloudflare-api-token` (cert-manager) | ClusterIssuer letsencrypt-prod (DNS-01) |

```bash
# Passwords fijos (opcional) en .env.local: ADMIN_PASSWORD, GRAFANA_ADMIN_PASSWORD,
# CLOUDFLARE_API_TOKEN. Sin ellos se generan aleatorios (cloudflare exige token real).
./scripts/generate-credentials.sh --component all   # o basic-auth|grafana|cloudflare
```

Reglas:
- Los `*-sealed.yaml` de `infra/bootstrap/secrets/` **sí se commitean** (solo el
  cluster contra el que se sellaron puede dessellarlos).
- En local/CI los secretos se regeneran al vuelo con valores dummy
  (`deploy-local.sh` y dev-ci lo hacen automáticamente; Grafana local: admin/admin).
- El password de admin de ArgoCD lo genera el propio chart:
  `kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d`

### Certificate Management
- **Local**: Self-signed wildcard certificates
- **Production**: Let's Encrypt wildcard certificates
- **Automatic renewal**: Handled by cert-manager

## 🧪 Testing & Validation

### Smoke Tests
```bash
# Run all tests
./tests/smoke.sh

# Tests include:
# - Pod readiness verification
# - Service availability
# - Application functionality
# - TLS certificate validation
# - Authentication testing
# - Resource utilization checks
```

### CI/CD Pipeline
- **Pull Requests**: Validation only (yamllint, helmfile lint, smoke tests)
- **Main Branch**: Full deployment pipeline with ArgoCD sync
- **Dev Branch**: Enhanced testing with manifest rendering
- **Concurrency control**: Prevents parallel runs

## 🔧 Development Workflow

### Making Changes

1. **Update versions** in `versions.env` if needed
2. **Modify applications** in `infra/apps/` or `infra/envs/`
3. **Test locally**:
```bash
# Validate changes
./scripts/deploy.sh minikube

# Run smoke tests
./tests/smoke.sh
```
4. **Commit and push** - CI will validate automatically

### Adding New Applications

1. **Create Helmfile** in `infra/apps/new-app/`
2. **Add to root Helmfile** in `infra/apps/helmfile.yaml`
3. **Create environment values** in `infra/envs/*/new-app-values.yaml`
4. **Expose it through the shared Gateway** with an `HTTPRoute` (el hostname es
   el único valor por entorno; el TLS lo termina el Gateway):
```yaml
# infra/envs/<entorno>/new-app-values.yaml
route:
  hostname: myapp.albertperez.dev   # o myapp.127.0.0.1.nip.io en minikube
```
```yaml
# HTTPRoute (en el chart o via extraObjects/extraManifests del chart upstream)
spec:
  parentRefs:
    - name: traefik-gateway
      namespace: traefik
      sectionName: websecure
```

## 📊 Monitoring & Debugging

### Useful Commands
```bash
# Check ArgoCD applications
kubectl get applications -n argocd
kubectl describe application cluster-root -n argocd

# View application logs
kubectl logs -n traefik -l app.kubernetes.io/name=traefik
kubectl logs -n hello -l app.kubernetes.io/name=hello

# Debug sealed secrets
kubectl get sealedsecrets -A
kubectl get secrets -A | grep admin-basic-auth

# Check certificates
kubectl get certificates -A
kubectl describe certificate wildcard-minikube
```

### Troubleshooting

**Common Issues:**
1. **ArgoCD not syncing**: Check application status and sync policies
2. **SealedSecrets not unsealing**: Verify controller is running in kube-system
3. **Domain resolution**: Ensure `.nip.io` domains resolve correctly
4. **Certificate issues**: Check cert-manager logs and issuer status

## 🤝 Contributing

1. **Follow the canonical structure**: Use centralized versions, global values
2. **Test changes locally**: Run smoke tests before committing
3. **Update documentation**: Keep README and comments current
4. **Security first**: Never commit secrets, use SealedSecrets

## 📚 Additional Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Helmfile Documentation](https://helmfile.readthedocs.io/)
- [Sealed Secrets](https://sealed-secrets.netlify.app/)
- [Cert-manager](https://cert-manager.io/)
- [Traefik](https://doc.traefik.io/traefik/)

---

**🎉 This cluster implementation demonstrates production-ready GitOps patterns with security, automation, and maintainability at its core.**

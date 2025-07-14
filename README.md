# Albert Cluster - Canonical GitOps with Helmfile + ArgoCD

A production-ready GitOps cluster implementation using ArgoCD and Helmfile, following DRY principles, idempotent operations, and security best practices.

## 🏗️ Architecture Overview

This project implements a **pure GitOps** approach where:
- **ArgoCD** manages cluster state from Git repository
- **Helmfile** renders application manifests with environment-specific values
- **Sealed Secrets** manages sensitive data securely
- **Cert-manager** provides TLS certificates (self-signed for dev, Let's Encrypt for prod)
- **Traefik** serves as ingress controller with authentication middleware

## 📁 Project Structure

```
albert-cluster/
├── versions.env                      # 🔧 Centralized version management
├── .yamllint.yml                     # 📝 YAML linting configuration
├── .pre-commit-config.yaml           # 🔧 Pre-commit hooks for code quality
├── .shellcheckrc                     # 🔧 Shell script linting configuration
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
│   │   ├── cert-manager/
│   │   │   ├── helmfile.yaml.gotmpl # 🔧 Helmfile v1+ template syntax
│   │   │   └── values.yaml
│   │   ├── sealed-secrets/
│   │   │   ├── helmfile.yaml.gotmpl # 🔧 Helmfile v1+ template syntax
│   │   │   └── values.yaml
│   │   ├── traefik/
│   │   │   ├── helmfile.yaml.gotmpl # 🔧 Helmfile v1+ template syntax
│   │   │   └── values.yaml
│   │   └── hello/
│   │       ├── helmfile.yaml.gotmpl # 🔧 Helmfile v1+ template syntax
│   │       └── values.yaml
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

### 🔍 Enhanced Validation & Code Quality
- **Pre-commit hooks**: Automatic whitespace fixes and validation
- **YAMLlint**: Consistent YAML formatting and syntax checking
- **Shellcheck**: Shell script linting with project-specific rules
- **Helmfile lint**: Helm template validation with proper .gotmpl syntax
- **Smoke tests**: Comprehensive functionality testing
- **Namespace consistency**: Verification across environments

## 🔧 Development Workflow

### One-time Setup

1. **Install pre-commit hooks**:
```bash
pip install pre-commit
pre-commit install
```

2. **Install required tools**:
```bash
# Source centralized versions
source versions.env

# Install Helmfile
curl -Lo helmfile https://github.com/helmfile/helmfile/releases/download/${HELMFILE_VERSION}/helmfile_linux_amd64
chmod +x helmfile && sudo mv helmfile /usr/local/bin/

# Install kubeseal
curl -Lo kubeseal https://github.com/bitnami-labs/sealed-secrets/releases/download/${KUBESEAL_VERSION}/kubeseal-linux-amd64
chmod +x kubeseal && sudo mv kubeseal /usr/local/bin/
```

### Making Changes

1. **Edit infrastructure files**:
```bash
# Edit application configurations
vim infra/apps/hello/values.yaml

# Edit environment-specific values
vim infra/envs/minikube/hello-values.yaml
```

2. **Validate changes locally**:
```bash
# Run all linting and validation
pre-commit run --all-files

# Test Helmfile rendering
cd infra/apps && source ../../versions.env && helmfile --environment minikube template

# Test deployment
./deploy-local.sh
```

3. **Run comprehensive tests**:
```bash
# Run smoke tests
./tests/smoke.sh

# Check specific components
kubectl get pods -A
kubectl get applications -n argocd
```

4. **Commit changes** (pre-commit hooks will auto-fix whitespace):
```bash
git add .
git commit -m "Update hello app configuration"
```

5. **Push to trigger CI/CD**:
```bash
git push origin main
```

### Code Quality Features

#### Pre-commit Hooks
- **Auto-fixes**: Trailing whitespace, missing newlines, line endings
- **Validation**: YAML syntax, merge conflicts, large files
- **Linting**: YAMLlint with flexible rules, Shellcheck with project config
- **File exclusions**: Properly excludes generated files and CRDs

#### YAMLlint Configuration
- **Flexible rules**: Warnings for line length and whitespace issues
- **Kubernetes-friendly**: Allows truthy values, custom indentation
- **Smart exclusions**: Ignores templates, CRDs, and generated files

#### Helmfile Template Syntax
- **Correct syntax**: Uses `{{ env "VARIABLE" }}` for environment variables
- **Gotmpl extension**: Uses `.gotmpl` for Helmfile v1+ template processing
- **Version injection**: Environment variables exported automatically in CI

### Troubleshooting Development Issues

#### Common Problems and Solutions

1. **Helmfile template errors**:
```bash
# Ensure environment variables are exported
source versions.env
export TRAEFIK_CHART_VERSION CERT_MANAGER_CHART_VERSION

# Check .gotmpl extensions are used
ls infra/apps/*/helmfile.yaml.gotmpl
```

2. **Pre-commit hook failures**:
```bash
# Run specific hook
pre-commit run yamllint --all-files

# Update hook versions
pre-commit autoupdate
```

3. **YAML validation issues**:
```bash
# Check for template syntax in plain YAML files
grep -r "{{" infra/ --include="*.yaml" --exclude-dir=templates

# Exclude problematic files in .yamllint.yml
```

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
minikube start --driver=docker --kubernetes-version=v1.29.2
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

1. **Configure secrets**:
```bash
# Generate secure credentials
./scripts/generate-credentials.sh --namespace admin --users "admin,ops"

# Configure Cloudflare API token for Let's Encrypt
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token=your-cloudflare-token \
  --namespace cert-manager
```

2. **Deploy to production**:
```bash
./scripts/deploy.sh netcup
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

### Sealed Secrets Management
```bash
# Generate new sealed secret
./scripts/generate-credentials.sh --namespace admin --users "user1,user2"

# The script will:
# 1. Generate secure passwords
# 2. Create bcrypt hashes
# 3. Seal the secret with kubeseal
# 4. Save to infra/bootstrap/secrets/
```

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
2. **Use pre-commit hooks**: Install and run pre-commit for automatic fixes
3. **Test changes locally**: Run smoke tests before committing
4. **Update documentation**: Keep README and comments current
5. **Security first**: Never commit secrets, use SealedSecrets

## 📚 Additional Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Helmfile Documentation](https://helmfile.readthedocs.io/)
- [Sealed Secrets](https://sealed-secrets.netlify.app/)
- [Cert-manager](https://cert-manager.io/)
- [Traefik](https://doc.traefik.io/traefik/)

---

**🎉 This cluster implementation demonstrates production-ready GitOps patterns with security, automation, and maintainability at its core.**

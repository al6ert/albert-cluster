# Albert Cluster

A GitOps-managed Kubernetes cluster repository using **Argo CD** for continuous deployment and infrastructure management.

[![CI/CD Pipeline](https://github.com/${{ github.repository }}/workflows/CI%2FCD%20Pipeline/badge.svg)](https://github.com/${{ github.repository }}/actions/workflows/ci.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Security Scan](https://github.com/${{ github.repository }}/workflows/Security%20Scan/badge.svg)](https://github.com/${{ github.repository }}/actions/workflows/ci.yaml)

## 📋 Table of Contents

- [Project Overview](#project-overview)
- [Repository Structure](#repository-structure)
- [Quick Installation](#quick-installation)
- [GitOps Architecture](#gitops-architecture)
- [CI/CD Pipeline](#cicd-pipeline)
- [Documentation](#documentation)
- [Contributing](#contributing)

## 🎯 Project Overview

Albert Cluster is a personal Kubernetes cluster managed through GitOps principles. All infrastructure and application configurations are version-controlled in this repository and automatically deployed using Argo CD.

### Key Features

- **GitOps-driven deployment** with Argo CD
- **Multi-environment support** (local development, production)
- **Automated CI/CD pipeline** with security scanning
- **Infrastructure as Code** using Kubernetes manifests and Helm charts
- **Comprehensive monitoring** and observability

## 📁 Repository Structure

```
albert-cluster/
├── .github/                    # GitHub Actions workflows
│   └── workflows/
│       ├── ci.yaml            # Main CI/CD pipeline
│       ├── monitoring.yaml    # Monitoring workflow
│       └── release.yaml       # Release automation
├── .dockerignore              # Docker ignore rules
├── .gitignore                 # Git ignore patterns
├── .yamllint                  # YAML linting configuration
├── CHANGELOG.md               # Project changelog
├── CONTRIBUTING.md            # Contribution guidelines
├── Dockerfile                 # Container image definition
├── LICENSE                    # MIT License
├── README.md                  # This file
├── docs/                      # Documentation
│   ├── gitops-pipeline.md     # GitOps and CI/CD details
│   ├── installation.md        # Installation guide
│   ├── minikube-local.md      # Local development setup
│   └── renovar-certificados-mkcert.md  # Certificate renewal
└── infra/                     # Infrastructure configuration
    ├── apps/                  # Applications managed by Argo CD
    │   ├── helmfile.yaml      # Helmfile for chart management
    │   └── traefik/           # Traefik ingress controller
    │       └── values.yaml    # Traefik configuration
    ├── bootstrap/             # Argo CD bootstrap configuration
    │   ├── argocd-root.yaml   # Root Argo CD application
    │   ├── argocd.yaml        # Argo CD installation
    │   ├── crds/              # Custom Resource Definitions
    │   │   └── traefik-crds.yaml
    │   ├── envs/              # Environment-specific configs
    │   │   └── netcup/
    │   │       └── argocd-values.yaml
    │   └── kustomization.yaml # Kustomize configuration
    ├── charts/                # Custom Helm charts
    │   └── hello/             # Example application chart
    │       ├── hello-deployment.yaml
    │       ├── hello-http-ingressroute.yaml
    │       ├── hello-ingressroute.yaml
    │       └── templates/     # Helm chart templates
    │           ├── test-deployment.yaml
    │           └── test-service.yaml
    ├── envs/                  # Environment-specific values
    │   ├── minikube/          # Local development environment
    │   │   └── traefik-values.yaml
    │   └── netcup/            # Production environment
    │       └── traefik-values.yaml
    └── README.md              # Infrastructure documentation
```

## 🚀 Quick Installation

### Prerequisites

- Kubernetes cluster (minikube for local development)
- `kubectl` configured to access your cluster
- `helm` (v3.x)
- `helmfile` (for managing multiple charts)

### Step 1: Install Argo CD

```bash
kubectl apply -f infra/bootstrap/argocd.yaml
kubectl apply -f infra/bootstrap/argocd-root.yaml
```

### Step 2: Deploy Applications

```bash
helmfile -f infra/apps/helmfile.yaml apply
```

### Step 3: Verify Argo CD Access

Ensure that the Argo CD UI is reachable. If you expose Traefik via a
`LoadBalancer` service, find the external IP and confirm your DNS record points
to it:

```bash
kubectl get svc -n kube-system traefik
```

If Argo CD itself runs with a `LoadBalancer`, check its service instead:

```bash
kubectl get svc -n argocd argocd-server
```

Initial access requires either a `LoadBalancer` service or a working Traefik
ingress so that the Argo CD endpoint is reachable through your firewall.

For detailed installation instructions, see the [Installation Guide](docs/installation.md).

## 🔄 GitOps Architecture

Este repositorio implementa GitOps puro:

- **Git es la única fuente de verdad** para toda la configuración.
- **Argo CD** monitoriza continuamente el repositorio y sincroniza los cambios automáticamente.
- **No se fuerza la sincronización manual** desde el pipeline CI/CD: ArgoCD gestiona todo el ciclo de vida de los recursos.
- **Toda la infraestructura y aplicaciones** se declaran como código y se gestionan por ArgoCD.

> **Nota:** El pipeline CI/CD nunca ejecuta comandos de sincronización ni refresh manual sobre ArgoCD. Todo el flujo es 100% GitOps: cualquier cambio en el repositorio se refleja automáticamente en el clúster mediante la reconciliación de ArgoCD.

### Repository Organization

- `infra/bootstrap/` - Argo CD installation and root application
- `infra/apps/` - Applications managed by Argo CD (Traefik, CRDs)
- `infra/envs/` - Environment-specific values (minikube, netcup)
- `infra/charts/` - Custom Helm charts for applications

For detailed GitOps information, see [GitOps and CI/CD Pipeline](docs/gitops-pipeline.md).

## ⚡ CI/CD Pipeline

El pipeline CI/CD sigue las mejores prácticas GitOps:

- **Validación & Linting:** Verifica sintaxis y calidad de los manifests y charts.
- **Escaneo de seguridad:** Analiza vulnerabilidades antes de desplegar.
- **Testing:** Ejecuta tests unitarios y de integración en un clúster efímero.
- **Despliegue GitOps:** Solo aplica manifests y confía en la reconciliación automática de ArgoCD. No se fuerza la sincronización ni el refresh manual.
- **Verificación post-deploy:** Solo verifica el estado de salud de las aplicaciones, sin intervenir en la reconciliación.

### Pipeline Stages

1. **Validate & Lint** - Syntax validation and linting
2. **Security Scan** - Vulnerability scanning
3. **Testing** - Unit and integration tests
4. **GitOps Deploy** - Manifests validation and push; ArgoCD auto-syncs changes
5. **Verify** - Post-deployment health checks

> **Importante:** El pipeline nunca fuerza la sincronización de ArgoCD. Todo el ciclo de vida de los recursos está gestionado por ArgoCD siguiendo el modelo GitOps puro.

## 📚 Documentation

- **[Installation Guide](docs/installation.md)** - Complete setup instructions
- **[GitOps and CI/CD Pipeline](docs/gitops-pipeline.md)** - Detailed pipeline information
- **[Local Development](docs/minikube-local.md)** - Minikube setup and local development
- **[Certificate Management](docs/renovar-certificados-mkcert.md)** - TLS certificate renewal

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)


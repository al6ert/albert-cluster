# GitOps and CI/CD Pipeline

This document describes the GitOps approach and CI/CD pipeline implemented in this project.

## GitOps Architecture

Este repositorio implementa GitOps puro:

- **Git es la única fuente de verdad** para toda la infraestructura y aplicaciones.
- **Argo CD** monitoriza continuamente el repositorio y sincroniza automáticamente los cambios en el clúster.
- **No se fuerza la sincronización ni el refresh manual** desde el pipeline CI/CD: ArgoCD gestiona todo el ciclo de vida de los recursos.
- **Toda la infraestructura y aplicaciones** se declaran como código y se gestionan por ArgoCD.

> **Diferencia clave con pipelines tradicionales:**
> En este flujo, el pipeline CI/CD nunca ejecuta comandos de sincronización ni refresh manual sobre ArgoCD. Todo el ciclo de vida de los recursos está gestionado por ArgoCD siguiendo el modelo GitOps puro. Cualquier cambio en el repositorio se refleja automáticamente en el clúster mediante la reconciliación de ArgoCD.

## Repository Structure

The repository is organized to support GitOps workflows:

- `infra/bootstrap/` - Contains manifests to install Argo CD and the root application
- `infra/apps/` - Applications managed by Argo CD (Traefik, CRDs, etc.)
- `infra/envs/` - Environment-specific values (minikube for local, netcup for production)
- `infra/charts/` - Custom Helm charts for applications

## CI/CD Pipeline

El pipeline CI/CD sigue las mejores prácticas GitOps:

- **Validación & Linting:** Verifica sintaxis y calidad de los manifests y charts.
- **Escaneo de seguridad:** Analiza vulnerabilidades antes de desplegar.
- **Testing:** Ejecuta tests unitarios y de integración en un clúster efímero.
- **Despliegue GitOps:** Solo aplica manifests y confía en la reconciliación automática de ArgoCD. No se fuerza la sincronización ni el refresh manual.
- **Verificación post-deploy:** Solo verifica el estado de salud de las aplicaciones, sin intervenir en la reconciliación.

### Pipeline Stages

1. **Validate & Lint** - YAML syntax validation and linting
2. **Security Scan** - Vulnerability scanning with Trivy
3. **Testing** - Unit and integration tests with kind
4. **GitOps Deploy** - Manifests validation and push; ArgoCD auto-syncs changes
5. **Verify** - Post-deployment health checks

> **Importante:** El pipeline nunca fuerza la sincronización de ArgoCD. Todo el ciclo de vida de los recursos está gestionado por ArgoCD siguiendo el modelo GitOps puro.

### Pipeline Features

- ✅ **Automatic validation** of YAML syntax and Helm charts
- ✅ **Security scanning** with Trivy
- ✅ **Unit and integration tests** with kind
- ✅ **Automatic deployment** to staging and production
- ✅ **Continuous monitoring** of the cluster
- ✅ **Semantic versioning** automation
- ✅ **Status notifications**

## Workflow Triggers

The pipeline is triggered by:

- **Push to main branch** - Deploys to production
- **Push to dev branch** - Deploys to staging
- **Pull requests** - Runs validation and tests
- **Releases** - Triggers full pipeline

## Security Features

- **Vulnerability scanning** with Trivy on every commit
- **Secret management** with proper .gitignore exclusions
- **RBAC** configured for Argo CD
- **Network policies** for pod-to-pod communication

## Monitoring and Observability

The pipeline includes:

- **Application health checks** post-deployment
- **Resource monitoring** and alerting
- **Log aggregation** and analysis
- **Performance metrics** collection

## Rollback Strategy

In case of deployment issues:

1. **Automatic rollback** through Argo CD
2. **Manual rollback** via Git revert
3. **Health check failures** trigger automatic rollback
4. **Monitoring alerts** for quick response

## Best Practices

- **Immutable tags** for Docker images
- **Declarative configuration** only
- **Environment parity** between staging and production
- **Infrastructure testing** before deployment
- **Documentation** updated with every change

For more information about the CI/CD configuration, see the workflow files in `.github/workflows/`. 
# Configuración de GitHub Environments

Este documento describe cómo configurar GitHub Environments separados para los entornos de desarrollo y producción, siguiendo las mejores prácticas de GitOps.

## Estructura de Environments

### Environment: `dev`
- **Propósito**: Entorno de desarrollo con Minikube
- **Branches**: `dev`, `feature/*`
- **Cluster**: Minikube local
- **Secrets**: Credenciales de desarrollo

### Environment: `prod`
- **Propósito**: Entorno de producción con Netcup
- **Branches**: `main`
- **Cluster**: Netcup Kubernetes
- **Secrets**: Credenciales de producción

## Configuración Manual en GitHub

### 1. Crear Environment `dev`

1. Ir a **Settings** > **Environments**
2. Hacer clic en **New environment**
3. Nombre: `dev`
4. Configurar **Protection rules**:
   - ✅ **Required reviewers**: 1 reviewer
   - ✅ **Wait timer**: 0 minutes
   - ✅ **Deployment branches**: `dev` y `feature/*`

### 2. Crear Environment `prod`

1. Ir a **Settings** > **Environments**
2. Hacer clic en **New environment**
3. Nombre: `prod`
4. Configurar **Protection rules**:
   - ✅ **Required reviewers**: 1 reviewer
   - ✅ **Wait timer**: 0 minutes
   - ✅ **Deployment branches**: `main`

## Secrets por Environment

### Environment `dev` Secrets

```yaml
# Secrets para desarrollo (Minikube)
MINIKUBE_KUBECONFIG: |
  apiVersion: v1
  kind: Config
  clusters:
  - name: minikube
    cluster:
      server: https://127.0.0.1:32768
  contexts:
  - name: minikube
    context:
      cluster: minikube
      user: minikube
  current-context: minikube
  users:
  - name: minikube
    user:
      token: <minikube-token>

# Variables de entorno para desarrollo
ENVIRONMENT: dev
CLUSTER_NAME: minikube
```

### Environment `prod` Secrets

```yaml
# Secrets para producción (Netcup)
NETCUP_KUBECONFIG: |
  apiVersion: v1
  kind: Config
  clusters:
  - name: netcup
    cluster:
      server: https://<netcup-server>:6443
      certificate-authority-data: <ca-data>
  contexts:
  - name: netcup
    context:
      cluster: netcup
      user: netcup-admin
  current-context: netcup
  users:
  - name: netcup-admin
    user:
      client-certificate-data: <cert-data>
      client-key-data: <key-data>

# Variables de entorno para producción
ENVIRONMENT: prod
CLUSTER_NAME: netcup

# ArgoCD credentials
ARGOCD_SERVER: https://argocd.albertperez.dev
ARGOCD_TOKEN: <argocd-token>
```

## Configuración de Branch Protection

### Rama `main`
- ✅ **Require a pull request before merging**
- ✅ **Require approvals**: 1 approval
- ✅ **Dismiss stale PR approvals when new commits are pushed**
- ✅ **Require status checks to pass before merging**
  - ✅ `build-test-dev` (dev environment)
- ✅ **Require branches to be up to date before merging**
- ✅ **Restrict pushes that create files that use the Git LFS**
- ✅ **Do not allow bypassing the above settings**

### Rama `dev`
- ✅ **Require a pull request before merging**
- ✅ **Require approvals**: 1 approval
- ✅ **Dismiss stale PR approvals when new commits are pushed**
- ✅ **Require status checks to pass before merging**
  - ✅ `build-test-dev` (dev environment)
- ✅ **Require branches to be up to date before merging**

## Workflow Configuration

### Dev Workflow (`.github/workflows/dev-ci-enhanced.yaml`)

```yaml
jobs:
  build-test-dev:
    environment: dev  # Usar environment dev
    runs-on: ubuntu-latest
    # ... resto del job
```

### Prod Workflow (`.github/workflows/ci.yaml`)

```yaml
jobs:
  promote-prod:
    environment: prod  # Usar environment prod
    needs: build-test-dev
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    # ... resto del job
```

## Flujo de Trabajo

### Desarrollo
1. Crear rama `feature/nueva-funcionalidad`
2. Hacer cambios y commits
3. Crear PR a `dev`
4. CI ejecuta tests en Minikube
5. Merge a `dev` si tests pasan

### Producción
1. Crear PR de `dev` a `main`
2. CI ejecuta tests en Minikube
3. Si tests pasan, merge a `main`
4. CI promueve a producción automáticamente
5. ArgoCD sincroniza en Netcup

## Seguridad

### Separación de Credenciales
- **Dev**: Solo acceso a Minikube local
- **Prod**: Solo acceso a cluster de Netcup
- **Nunca mezclar**: Credenciales de dev y prod

### Rotación de Credenciales
- Rotar credenciales cada 90 días
- Usar Sealed Secrets para almacenamiento seguro
- Documentar proceso de rotación

## Troubleshooting

### Problemas Comunes

1. **Environment no encontrado**
   - Verificar que el environment existe en GitHub
   - Verificar que el workflow especifica el environment correcto

2. **Secrets no disponibles**
   - Verificar que los secrets están configurados en el environment
   - Verificar permisos del workflow

3. **Branch protection bloquea merge**
   - Verificar que los status checks pasan
   - Verificar que hay approvals suficientes

### Comandos Útiles

```bash
# Verificar environments disponibles
gh api repos/:owner/:repo/environments

# Verificar secrets de un environment
gh api repos/:owner/:repo/environments/:environment/protection_rules
```

## Referencias

- [GitHub Environments Documentation](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
- [Branch Protection Rules](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches)
- [GitHub Actions Security](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions) 
# GitOps Pipeline con Helmfile + ArgoCD

Este documento describe la arquitectura GitOps implementada usando Helmfile para renderizado y ArgoCD para despliegue automático.

## 🏗️ Arquitectura GitOps

### Flujo de Trabajo
```
1. Desarrollo → 2. Helmfile Render → 3. YAML Plano → 4. ArgoCD Sync
```

### Componentes Principales

#### Helmfile
- **Propósito**: Renderizar manifiestos YAML desde charts y values
- **Ubicación**: `infra/apps/helmfile.yaml`
- **Entornos**: `minikube` y `netcup`

#### ArgoCD
- **Propósito**: Sincronizar manifiestos YAML con el cluster
- **Aplicaciones**: 
  - `cluster-root` → `infra/rendered/netcup/`
  - `cluster-minikube` → `infra/rendered/minikube/`

## 🔄 Pipeline CI/CD

### Workflow: render.yaml

Renderiza manifiestos de ambos entornos usando Helmfile.

```yaml
name: Render Manifests
on:
  push:
    branches: [main, dev]
  workflow_dispatch:

jobs:
  render:
    runs-on: ubuntu-latest
    steps:
      - name: Install Helmfile
        run: |
          curl -L https://github.com/helmfile/helmfile/releases/download/v0.162.0/helmfile_0.162.0_linux_amd64.tar.gz | tar xz
          sudo mv helmfile /usr/local/bin/

      - name: Render manifests for minikube
        run: |
          cd infra/apps
          helmfile --environment minikube template > ../rendered/minikube/all.yaml

      - name: Render manifests for netcup
        run: |
          cd infra/apps
          helmfile --environment netcup template > ../rendered/netcup/all.yaml
```

### Workflow: ci.yaml

Valida los manifiestos renderizados y prepara para ArgoCD.

```yaml
name: CI
on:
  push:
    branches: [main, dev]
  pull_request:
    branches: [main, dev]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - name: Validate rendered manifests
        run: |
          kubectl apply --dry-run=client -f infra/rendered/minikube/all.yaml
          kubectl apply --dry-run=client -f infra/rendered/netcup/all.yaml

      - name: Lint YAML files
        run: |
          yamllint infra/rendered/minikube/all.yaml
          yamllint infra/rendered/netcup/all.yaml
```

## 📁 Estructura de Archivos

### Configuración de Aplicaciones
```
infra/apps/
├── helmfile.yaml              # Helmfile raíz
├── hello/
│   ├── helmfile.yaml          # Configuración específica de Hello
│   └── values.yaml            # Valores base de Hello
└── traefik/
    ├── helmfile.yaml          # Configuración específica de Traefik
    └── values.yaml            # Valores base de Traefik
```

### Valores por Entorno
```
infra/envs/
├── minikube/
│   ├── global-values.yaml     # Valores globales para desarrollo
│   ├── hello-values.yaml      # Valores específicos de Hello
│   └── traefik-values.yaml    # Valores específicos de Traefik
└── netcup/
    ├── global-values.yaml     # Valores globales para producción
    ├── hello-values.yaml      # Valores específicos de Hello
    └── traefik-values.yaml    # Valores específicos de Traefik
```

### Manifiestos Renderizados
```
infra/rendered/
├── minikube/
│   └── all.yaml               # YAML renderizado para desarrollo
└── netcup/
    └── all.yaml               # YAML renderizado para producción
```

## 🚀 Despliegue

### Desarrollo Local (Minikube)

1. **Renderizar manifiestos**:
   ```bash
   cd infra/apps
   helmfile --environment minikube template
   ```

2. **Aplicar bootstrap de ArgoCD**:
   ```bash
   kubectl apply -k infra/bootstrap/
   ```

3. **ArgoCD sincroniza automáticamente** desde `infra/rendered/minikube/`

### Producción (Netcup)

1. **Renderizar manifiestos**:
   ```bash
   cd infra/apps
   helmfile --environment netcup template
   ```

2. **Aplicar bootstrap de ArgoCD**:
   ```bash
   kubectl apply -k infra/bootstrap/
   ```

3. **ArgoCD sincroniza automáticamente** desde `infra/rendered/netcup/`

## 🔧 Configuración de ArgoCD

### Aplicación Root (Producción)
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-root
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/al6ert/albert-cluster.git
    targetRevision: main
    path: infra/rendered/netcup
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Aplicación Minikube (Desarrollo)
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-minikube
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/al6ert/albert-cluster.git
    targetRevision: dev
    path: infra/rendered/minikube
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## 🛠️ Desarrollo

### Agregar Nueva Aplicación

1. **Crear estructura de la aplicación**:
   ```bash
   mkdir -p infra/apps/nueva-app
   ```

2. **Crear helmfile.yaml**:
   ```yaml
   releases:
     - name: nueva-app
       namespace: traefik
       chart: nueva-app/nueva-app
       values:
         - values.yaml
         - ../../envs/{{ .Environment.Name }}/nueva-app-values.yaml
   ```

3. **Crear values.yaml base**:
   ```yaml
   # infra/apps/nueva-app/values.yaml
   replicaCount: 1
   image:
     repository: nginx
     tag: "alpine"
   ```

4. **Agregar valores por entorno**:
   ```bash
   # infra/envs/minikube/nueva-app-values.yaml
   replicaCount: 1
   
   # infra/envs/netcup/nueva-app-values.yaml
   replicaCount: 2
   ```

5. **Incluir en helmfile raíz**:
   ```yaml
   # infra/apps/helmfile.yaml
   releases:
     - name: nueva-app
       # ... configuración
   ```

### Modificar Configuración

1. **Editar values** en `infra/envs/<entorno>/`
2. **El pipeline renderiza automáticamente** los cambios
3. **ArgoCD sincroniza** los nuevos manifiestos

## 🔍 Monitoreo y Debugging

### Verificar Estado de ArgoCD
```bash
kubectl get applications -n argocd
kubectl describe application cluster-root -n argocd
```

### Verificar Manifiestos Renderizados
```bash
# Ver manifiestos de minikube
cat infra/rendered/minikube/all.yaml

# Ver manifiestos de netcup
cat infra/rendered/netcup/all.yaml
```

### Debugging de Helmfile
```bash
cd infra/apps
helmfile --environment minikube template --debug
helmfile --environment netcup template --debug
```

## 🎯 Ventajas de esta Arquitectura

### Simplicidad
- **Un solo tool**: Helmfile para toda la gestión
- **Sin plugins**: ArgoCD vanilla sin dependencias externas
- **YAML plano**: Fácil de revisar y debuggear

### Consistencia
- **Mismo flujo**: Para desarrollo y producción
- **Valores centralizados**: Fácil gestión de configuración
- **Renderizado automático**: Sin errores manuales

### Auditabilidad
- **YAML en Git**: Trazabilidad completa
- **Sin sidecars**: ArgoCD puro
- **Historial claro**: Cambios visibles en el repositorio

## 🔗 Enlaces Útiles

- [Helmfile Documentation](https://helmfile.readthedocs.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Traefik Documentation](https://doc.traefik.io/traefik/) 
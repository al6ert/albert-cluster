# Albert Cluster - GitOps con Helmfile + ArgoCD

Infraestructura Kubernetes gestionada con GitOps usando Helmfile para renderizado y ArgoCD para despliegue automático.

## 🏗️ Arquitectura

### Flujo GitOps
```
Helmfile (render) → YAML plano → ArgoCD (deploy)
```

### Estructura del Proyecto
```
.
├── .github/workflows/
│   ├── ci.yaml              # Renderiza y valida manifiestos
│   ├── monitoring.yaml
│   └── release.yaml
├── infra/
│   ├── apps/
│   │   ├── helmfile.yaml    # Helmfile raíz con todas las aplicaciones
│   │   ├── hello/
│   │   │   ├── helmfile.yaml
│   │   │   └── values.yaml
│   │   ├── cert-manager/
│   │   │   ├── helmfile.yaml
│   │   │   └── values.yaml
│   │   └── traefik/
│   │       ├── helmfile.yaml
│   │       └── values.yaml
│   ├── envs/
│   │   ├── minikube/        # Configuración para desarrollo
│   │   └── netcup/          # Configuración para producción
│   ├── rendered/
│   │   ├── minikube/        # YAML renderizado para desarrollo
│   │   └── netcup/          # YAML renderizado para producción
│   ├── charts/
│   │   └── hello/           # Chart personalizado
│   └── bootstrap/           # Configuración de ArgoCD
├── docs/
└── scripts/
```

## 🚀 Inicio Rápido

### Prerrequisitos
- Kubernetes cluster (minikube, kind, o producción)
- ArgoCD instalado
- Helmfile
- kubectl

### Despliegue Local (Minikube)
```bash
# 1. Renderizar manifiestos
cd infra/apps
helmfile --environment minikube template

# 2. Aplicar bootstrap (ArgoCD)
kubectl apply -k infra/bootstrap/

# 3. ArgoCD sincronizará automáticamente desde infra/rendered/minikube/
```

### Despliegue en Producción
```bash
# 1. Renderizar manifiestos
cd infra/apps
helmfile --environment netcup template

# 2. Aplicar bootstrap (ArgoCD)
kubectl apply -k infra/bootstrap/

# 3. ArgoCD sincronizará automáticamente desde infra/rendered/netcup/
```

## 🔄 Pipeline CI/CD

### Workflows de GitHub Actions

1. **ci.yaml**: Renderiza y valida manifiestos de ambos entornos
   - Se ejecuta en push a `main` o `dev`
   - Renderiza YAML con Helmfile
   - Valida sintaxis y estructura
   - Prepara para sincronización de ArgoCD

### ArgoCD Applications

- **cluster-root**: Sincroniza desde `infra/rendered/netcup/` (producción)
- **cluster-minikube**: Sincroniza desde `infra/rendered/minikube/` (desarrollo)

## 📦 Aplicaciones

### Traefik
- Ingress controller con Let's Encrypt
- Dashboard habilitado
- Configuración específica por entorno

### Hello
- Aplicación de ejemplo
- Chart personalizado
- Configuración específica por entorno

## 🌍 Entornos

### Minikube (Desarrollo)
- Dominio: `127.0.0.1.nip.io`
- Sin persistencia
- Configuración simplificada

### Netcup (Producción)
- Dominio: `albertperez.dev`
- Let's Encrypt habilitado
- Persistencia configurada

## 🛠️ Desarrollo

### Agregar Nueva Aplicación
1. Crear `infra/apps/<app>/helmfile.yaml`
2. Crear `infra/apps/<app>/values.yaml`
3. Agregar valores por entorno en `infra/envs/`
4. Incluir en `infra/apps/helmfile.yaml`

### Modificar Configuración
1. Editar values en `infra/envs/<entorno>/`
2. El pipeline renderizará automáticamente
3. ArgoCD sincronizará los cambios

## 📚 Documentación

- [Instalación](docs/installation.md)
- [Pipeline GitOps](docs/gitops-pipeline.md)
- [Desarrollo Local](docs/minikube-local.md)

## 🤝 Contribución

Ver [CONTRIBUTING.md](CONTRIBUTING.md) para detalles sobre el proceso de contribución.

## 📄 Licencia

Este proyecto está bajo la Licencia MIT - ver [LICENSE](LICENSE) para detalles.


# Albert Cluster

Repositorio GitOps para gestionar mi clúster personal con **Argo CD**.
Toda la configuración de Kubernetes vive en este repositorio.

[![CI/CD Pipeline](https://github.com/${{ github.repository }}/workflows/CI%2FCD%20Pipeline/badge.svg)](https://github.com/${{ github.repository }}/actions/workflows/ci.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Security Scan](https://github.com/${{ github.repository }}/workflows/Security%20Scan/badge.svg)](https://github.com/${{ github.repository }}/actions/workflows/ci.yaml)

## 🚀 CI/CD Pipeline

Este proyecto incluye un pipeline completo de CI/CD con:

- ✅ **Validación automática** de sintaxis YAML y Helm charts
- ✅ **Escaneo de seguridad** con Trivy
- ✅ **Tests unitarios e integración** con kind
- ✅ **Despliegue automático** a staging y producción
- ✅ **Monitoreo continuo** del cluster
- ✅ **Versionado semántico** automático
- ✅ **Notificaciones** de estado

### Pipeline Stages:

1. **Validate & Lint** - Validación de sintaxis y linting
2. **Security Scan** - Escaneo de vulnerabilidades
3. **Build & Push** - Construcción y publicación de imágenes
4. **Testing** - Tests unitarios e integración
5. **Deploy Staging** - Despliegue a entorno de pruebas
6. **Deploy Production** - Despliegue a producción
7. **Verify** - Verificación post-despliegue
8. **Notify** - Notificaciones de estado

## Puesta en marcha rápida

Instala Argo CD y la aplicación raíz que sincronizará `infra/bootstrap`:

```bash
kubectl apply -f infra/bootstrap/argocd.yaml
kubectl apply -f infra/bootstrap/argocd-root.yaml
```

Tras ello Argo CD aplicará automáticamente los charts y manifiestos
definidos en `infra/bootstrap` (por ejemplo Traefik y sus CRDs). 

Kustomization File para Argo CD

Uso de Hhelmfile para gestionar los charts:

```bash
helmfile -f infra/apps/helmfile.yaml apply
```

## Estructura del repositorio

- `infra/bootstrap` contiene los manifiestos para instalar Argo CD y la
  aplicación raíz que apunta a `infra/apps`.
- `infra/apps` es la carpeta que Argo CD sincroniza; aquí se definen las
  aplicaciones y charts del clúster.
- `infra/envs` guarda valores específicos por entorno (p.ej. `minikube` y
  `netcup`).
- `docs` almacena la documentación de soporte.

## Acceso

Conecta al VPS con SSH:

```bash
ssh netcup
```

## hostname
albertperez 

La configuración de `kubectl` está en `kubeconfig ~/.kube/config`.


## Comandos básicos de Kubernetes

### local
```bash
kubectl config use-context minikube
```
### remote
```bash
kubectl config use-context netcup
```

```bash
kubectl config current-context  # Ver contexto actual
kubectl get nodes               # Ver nodos
kubectl get pods -A             # Todos los pods y namespaces
kubectl logs deploy/nginx       # Logs de un Deployment
kubectl apply -f archivo.yml    # Crear/actualizar recursos
kubectl delete -f archivo.yml
```

## Documentación

### local
- [Minikube local](docs/minikube-local.md)
- [Renovar certificados TLS con mkcert](docs/renovar-certificados-mkcert.md)


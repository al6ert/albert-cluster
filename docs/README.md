# Documentación — Albert Cluster

Cluster GitOps personal sobre Kubernetes (Minikube en local, VPS Netcup en
producción) gestionado con **Helmfile + ArgoCD**, secretos con **SealedSecrets**,
TLS con **cert-manager** y exposición con **Traefik + Gateway API**.

## Índice

| Página | Contenido |
|--------|-----------|
| [architecture.md](architecture.md) | Flujo GitOps, componentes, sync-waves, red (Gateway API), entornos y ramas. |
| [deployment.md](deployment.md) | Despliegue **local** (minikube) y **producción** (netcup), y pipeline CI/CD. |
| [scripts.md](scripts.md) | Qué hace cada `.sh`, cuándo ejecutarlo y cuál sobra. |
| [secrets.md](secrets.md) | Gestión de secretos/contraseñas: SealedSecrets, `.env.local`, rotación. |
| [apps.md](apps.md) | Cada aplicación: chart, versión, namespace, rol y **link a doc oficial**. |
| [adding-apps.md](adding-apps.md) | Cómo añadir una app nueva paso a paso + checklist. |
| [updates.md](updates.md) | Actualizaciones automáticas de charts con **reglas de seguridad** (no actualizar nada con <7 días). |
| [assessment.md](assessment.md) | **Rúbrica del estado actual** desde múltiples perspectivas + backlog priorizado. |

## TL;DR

```bash
# Local (minikube)
source versions.env
minikube start --driver=docker --kubernetes-version=${KUBERNETES_VERSION}
./deploy-local.sh
./tests/smoke.sh

# Producción (una sola vez, kubectl apuntando a netcup)
./scripts/bootstrap-prod.sh
# A partir de ahí: push a main → CI sincroniza ArgoCD (GitOps puro)
```

## Convenciones del repo

- **`versions.env`** es la fuente de verdad de versiones (charts y herramientas).
- **Local = rama `dev`** (ArgoCD app `cluster-minikube`), **producción = rama `main`**
  (ArgoCD app `cluster-root`).
- Los secretos viven sellados en `infra/bootstrap/secrets/*-sealed.yaml` y **sí**
  se commitean (solo el cluster que los selló puede abrirlos).
- Las apps se exponen con **`HTTPRoute` → Gateway API** (`traefik-gateway`), no con
  `Ingress`. Ver [architecture.md](architecture.md#red).

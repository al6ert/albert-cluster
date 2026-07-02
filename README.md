# Albert Cluster — GitOps con Helmfile + ArgoCD

Cluster Kubernetes personal gestionado con **GitOps puro**: el repositorio es la
única fuente de verdad y **ArgoCD** reconcilia el cluster ejecutando **Helmfile**.
Corre en **Minikube** (local) y en un **VPS Netcup** (producción).

```
ArgoCD ──watch──► repo ──helmfile──► cert-manager · sealed-secrets · traefik(Gateway API) · argocd · prometheus · hello
```

- **Secretos**: SealedSecrets (un solo mecanismo, cifrado en Git).
- **TLS**: cert-manager (CA local en dev, Let's Encrypt DNS-01 en prod).
- **Red**: Traefik como implementación de **Gateway API**; las apps exponen
  `HTTPRoute` (no `Ingress`).
- **Versiones**: pineadas en [`versions.env`](versions.env).

## 📚 Documentación

La documentación detallada está en [`docs/`](docs/README.md):

| Página | Contenido |
|--------|-----------|
| [Arquitectura](docs/architecture.md) | Flujo GitOps, componentes, sync-waves, red, entornos y ramas. |
| [Despliegue](docs/deployment.md) | Local (minikube) y producción (netcup) + CI/CD. |
| [Scripts](docs/scripts.md) | Qué hace cada `.sh` y cuál sobra. |
| [Secretos](docs/secrets.md) | SealedSecrets, `.env.local`, rotación, passwords. |
| [Apps](docs/apps.md) | Cada aplicación con link a su doc oficial. |
| [Añadir apps](docs/adding-apps.md) | Paso a paso + checklist. |
| [Actualizaciones](docs/updates.md) | Auto-updates con reglas de seguridad (no actualizar nada con <7 días). |
| [**Rúbrica / estado**](docs/assessment.md) | Evaluación multi-perspectiva + backlog priorizado. |

## 🚀 Quick start

```bash
# Local (minikube)
source versions.env
minikube start --driver=docker --kubernetes-version=${KUBERNETES_VERSION}
./deploy-local.sh        # idempotente: bootstrap + apps + secretos dummy locales
./tests/smoke.sh

# Producción (una sola vez, kubectl apuntando a netcup)
./scripts/generate-credentials.sh --component all   # con .env.local relleno
./scripts/bootstrap-prod.sh
# Después: push a main → CI sincroniza ArgoCD (GitOps puro)
```

### Acceso local

| Servicio | URL |
|----------|-----|
| Hello | `http://hello.127.0.0.1.nip.io` |
| Traefik dashboard | `https://traefik.127.0.0.1.nip.io/dashboard/` |
| ArgoCD | `https://argo.127.0.0.1.nip.io` (admin / ver [secretos](docs/secrets.md#argocd)) |
| Grafana | `https://grafana.127.0.0.1.nip.io` (admin / admin) |

## 🗂️ Estructura

```
albert-cluster/
├── versions.env          # Fuente de verdad de versiones
├── deploy-local.sh       # Despliegue local idempotente
├── docs/                 # Documentación (ver índice arriba)
├── scripts/              # bootstrap-prod · generate-credentials · deploy(⚠️ ver docs)
├── tests/smoke.sh        # Smoke tests
├── .github/workflows/    # CI (main/PR) y dev-ci (rama dev)
└── infra/
    ├── bootstrap/        # CRDs, namespaces, RBAC, middlewares, secretos sellados, Apps de ArgoCD
    ├── apps/             # Un sub-helmfile por app + helmfile.yaml raíz
    ├── envs/             # Overrides por entorno (minikube / netcup)
    └── charts/hello/     # Chart local de ejemplo
```

## 📖 Recursos oficiales

[ArgoCD](https://argo-cd.readthedocs.io/) ·
[Helmfile](https://helmfile.readthedocs.io/) ·
[Sealed Secrets](https://github.com/bitnami/sealed-secrets) ·
[cert-manager](https://cert-manager.io/) ·
[Traefik](https://doc.traefik.io/traefik/) ·
[Gateway API](https://gateway-api.sigs.k8s.io/)

## 🤝 Contribuir

Ver [CONTRIBUTING.md](CONTRIBUTING.md). En esencia: cambios en rama `dev` →
validados en minikube por CI → promoción a `main` → ArgoCD a producción. Nunca
`helmfile apply` a mano en producción.

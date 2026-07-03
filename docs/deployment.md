# Despliegue

Dos caminos: **local** (Minikube, para desarrollar) y **producción** (Netcup,
GitOps vía ArgoCD). En local se despliega directo con Helmfile; en producción
solo se hace bootstrap una vez y a partir de ahí manda Git.

---

## Local (Minikube)

### Requisitos

Herramientas (versiones recomendadas en [`versions.env`](../versions.env)):
`docker`, `minikube`, `kubectl`, `helm`, `helmfile`, `kubeseal`, `jq`,
`htpasswd` (paquete `apache2-utils`), `openssl`.

```bash
source versions.env
minikube start --driver=docker --kubernetes-version=${KUBERNETES_VERSION}
```

### Desplegar

```bash
./deploy-local.sh
```

`deploy-local.sh` es **idempotente** y hace, en orden:

1. Desactiva el addon `ingress` de minikube (evita choque con Traefik).
2. **Bootstrap**: aplica `namespaces/`, `crds/` (server-side), `rbac/`,
   `middlewares/`.
3. Instala el controller de **SealedSecrets** y espera a que esté listo.
4. **Genera secretos dummy locales** en un dir temporal (no toca los
   `*-sealed.yaml` de producción del repo): basic-auth `admin/admin`, Grafana
   `admin/admin`, auth del Redis de ArgoCD y token Cloudflare ficticio.
5. Habilita **metallb** como LoadBalancer (rango derivado de `minikube ip`), para
   que el `Service` de Traefik obtenga IP sin `minikube tunnel`.
6. Aplica el resto de apps con Helmfile (`--selector name!=sealed-secrets`).
7. Aplica la Application de ArgoCD `cluster-minikube` (si
   `DEPLOY_ARGOCD_APPS=true`, que es el default).
8. Imprime URLs y credenciales generadas.

> Variable útil: `DEPLOY_ARGOCD_APPS=false ./deploy-local.sh` despliega solo con
> Helmfile, sin instalar las Applications de ArgoCD.

### Verificar

```bash
./tests/smoke.sh
kubectl get pods -A
kubectl get applications -n argocd
```

### Acceso local

| Servicio | URL | Credenciales |
|----------|-----|--------------|
| Hello | `http://hello.127.0.0.1.nip.io` | — |
| Traefik dashboard | `https://traefik.127.0.0.1.nip.io/dashboard/` | sin auth en local |
| ArgoCD | `https://argo.127.0.0.1.nip.io` | `admin` / ver [secrets.md](secrets.md#argocd) |
| Grafana | `https://grafana.127.0.0.1.nip.io` | `admin` / `admin` |

Certificados self-signed (CA local) → el navegador avisará; es esperado en local.

---

## Producción (Netcup)

### Bootstrap (una sola vez)

Con `kubectl` apuntando al cluster de producción:

```bash
# 1. Genera y sella los secretos reales contra ESTE cluster
#    (pon los valores reales en .env.local: ADMIN_PASSWORD,
#     GRAFANA_ADMIN_PASSWORD, CLOUDFLARE_API_TOKEN)
./scripts/generate-credentials.sh --component all
git add infra/bootstrap/secrets/*-sealed.yaml
git commit -m 'chore: rotate sealed secrets'

# 2. Bootstrap del cluster
./scripts/bootstrap-prod.sh
```

`bootstrap-prod.sh` aplica CRDs/namespaces/RBAC/middlewares, instala los
componentes core en orden (cert-manager → sealed-secrets → traefik → argocd),
aplica los `*-sealed.yaml` y finalmente crea la Application raíz `cluster-root`.
A partir de aquí, **ArgoCD se encarga de todo**.

### Flujo del día a día (GitOps)

```
editar infra/** en rama main  →  push  →  CI (promote-prod)  →  argocd app sync cluster-root
```

No se ejecuta Helmfile a mano en producción. Para previsualizar un cambio se usa
la rama `dev` (que despliega contra minikube en CI) o `argocd app diff`.

### Requisitos de infraestructura (fuera del repo)

- **DNS wildcard** `*.albertperez.dev` → IP del VPS (necesario para que nuevas
  apps resuelvan sin tocar DNS por cada una).
- **Cloudflare API token** con permisos DNS para el challenge DNS-01 de
  Let's Encrypt (cert-manager).
- Puertos 80/443 accesibles hacia el `Service` LoadBalancer de Traefik.

---

## CI/CD

| Workflow | Trigger | Qué hace |
|----------|---------|----------|
| `.github/workflows/ci.yaml` — job `integration-test` | PR a `main` | Valida manifiestos minikube+netcup, consistencia de namespaces, levanta minikube, corre `deploy-local.sh` + smoke tests. |
| `.github/workflows/ci.yaml` — job `promote-prod` | push a `main` | `argocd app diff cluster-root` y, si hay cambios, `argocd app sync --prune`. |
| `.github/workflows/dev-ci*.yaml` | push/PR a `dev` | Bootstrap por fases en minikube + render + smoke tests (build de desarrollo). |

Concurrencia con `cancel-in-progress` para no solapar runs. Permisos mínimos
(`contents: read`).

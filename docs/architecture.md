# Arquitectura

## Modelo: GitOps puro

El repositorio Git es la **única fuente de verdad**. Nadie aplica manifiestos a
mano en producción: ArgoCD observa el repo y reconcilia el cluster.

```
 Git (este repo)                    Cluster
 ┌────────────────────┐            ┌────────────────────────────────────────┐
 │ infra/apps/        │   watch    │  ApplicationSet "cluster-apps"         │
 │  <app>/app.yaml ───┼──────────► │   (git files generator)                │
 │  <app>/helmfile…   │            │     │ genera 1 Application POR APP     │
 │ infra/envs/        │            │     ▼                                  │
 │ infra/charts/      │            │  Application <app> → plugin "helmfile" │
 └────────────────────┘            │     │ helmfile template (en el dir     │
        ▲                          │     ▼  de la app)                      │
        │ git push                 │  apply (prune, self-heal, retry)       │
        │                          └────────────────────────────────────────┘
 ┌──────┴───────┐
 │  GitHub CI   │  (en main: argocd app sync -l cluster=netcup + wait --health)
 └──────────────┘
```

- **Una Application por app** (generadas por el ApplicationSet
  `infra/bootstrap/appset-<entorno>.yaml` a partir de los
  `infra/apps/<app>/app.yaml`): salud y sync granulares, una app rota no
  frena a las demás, y **crear carpeta = alta de app** (ver
  [adding-apps.md](adding-apps.md)).
- **ArgoCD** ejecuta Helmfile a través de un *config management plugin* (CMP).
  No hay manifiestos renderizados versionados; ArgoCD renderiza en vivo.
- **Helmfile** combina, por cada app, su chart upstream + `values.yaml` base +
  `infra/envs/<entorno>/<app>-values.yaml`. El helmfile raíz
  (`infra/apps/helmfile.yaml`) queda para deploy-local/bootstrap/CI; la CI
  exige que toda app esté registrada en ambos sitios.
- **Versiones de chart**: fuente única en [`versions.env`](../versions.env). El
  plugin hace `source versions.env` del propio checkout antes de renderizar, así
  que Git manda también en las versiones. (Nota: inyectarlas como `env:` de la
  Application **no** funciona — ArgoCD las prefija como `ARGOCD_ENV_*` y helmfile
  no las vería.)

## Entorno de producción (verificado 2026-07-03)

| Ítem | Valor |
|------|-------|
| Proveedor | VPS Netcup, IP `188.68.42.77` (acceso `ssh netcup`) |
| SO | Ubuntu 22.04.5 LTS (kernel 5.15) |
| Kubernetes | **kubeadm v1.33.2**, nodo único `albertperez` |
| Runtime | containerd 2.2.1 |
| CNI | **flannel** — ⚠️ *no aplica `NetworkPolicy`* (sin enforcement; las políticas serían declarativas hasta migrar a Cilium/Calico) |
| Recursos | 8 vCPU · 16 GiB RAM · 1 TB disco (`/dev/vda3`) · sin swap |
| LoadBalancer | el `Service` de Traefik obtiene la IP del propio nodo |

⚠️ **Certificados del plano de control**: kubeadm los emite a **1 año** (los del
cluster caducaron el 2026-06-29 y dejaron el API server inaccesible — los
workloads siguieron sirviendo). Renovación: `kubeadm certs renew all` + reinicio
del plano de control + refrescar `admin.conf` local. `kubeadm upgrade` también
los renueva de paso. Hay que vigilar su expiración (ver
[runbooks](runbooks/disaster-recovery.md)).

El kubelet tiene rotación automática de su certificado de cliente (verificado:
rotó solo en abril). Las CAs valen hasta 2035.

## Ramas y entornos

| Entorno | Rama | ArgoCD Application | Contexto kubectl | Dominio |
|---------|------|--------------------|------------------|---------|
| Local (Minikube) | `dev` | `cluster-minikube` | `minikube` | `127.0.0.1.nip.io` |
| Producción (Netcup) | `main` | `cluster-root` | `netcup` | `albertperez.dev` |

`nip.io` resuelve cualquier `*.127.0.0.1.nip.io` a `127.0.0.1`, así no hace falta
tocar `/etc/hosts` en local.

## Componentes y orden de despliegue (sync-waves)

El orden lo define `infra/apps/helmfile.yaml` (los `helmfiles:` se aplican en orden):

| Wave | App | Rol |
|------|-----|-----|
| 0 | **cert-manager** | Emite certificados TLS (CA local en dev, Let's Encrypt DNS-01 en prod). |
| 0 | **sealed-secrets** | Controller que descifra los `SealedSecret` → `Secret`. |
| 1 | **traefik** | Ingress controller / **implementación de Gateway API** + LoadBalancer de entrada. |
| 2 | **argocd** | El propio GitOps (se autogestiona tras el bootstrap). |
| 3 | **hello** | App de ejemplo / canario (chart local en `infra/charts/hello`). |
| 3 | **prometheus** | `kube-prometheus-stack` — en retirada, sustituido por `monitoring` (ver [observability.md](observability.md)). |
| 3 | **monitoring** | Grafana Alloy → Grafana Cloud (solo netcup). |
| 3 | **velero** | Backups a Cloudflare R2 (solo netcup; [runbook DR](runbooks/disaster-recovery.md)). |
| 3 | **policies** | NetworkPolicy + ResourceQuota + LimitRange por namespace de app. |

> El "wave" es **documental** en el modelo per-app: cada Application se
> reconcilia independiente con `retry`; el orden real de arranque en frío lo
> dan los scripts de bootstrap. El orden del helmfile raíz sigue aplicando en
> `deploy-local.sh`/`bootstrap-prod.sh`.

Las **CRDs** (cert-manager, traefik, gateway-api, prometheus, sealed-secrets,
argo, alloy, velero) **no** las instalan los charts: viven en
`infra/bootstrap/crds/` y se aplican con `kubectl apply --server-side` antes
que nada. Esto evita el problema clásico de Helm con CRDs y los
`--server-side` evita conflictos de tamaño.

## Fiabilidad en un nodo (asunción explícita)

Este cluster es **single-node a propósito** (homelab/VPS): no hay HA real.
`replicaCount > 1` y `PodDisruptionBudget` **no aportan** disponibilidad aquí
(mismo nodo) — no se usan por defecto. La estrategia de fiabilidad es:
reconstrucción rápida desde Git ([runbook DR](runbooks/disaster-recovery.md)),
backups fuera del VPS (velero → R2) y alerting fuera del cluster
([observability.md](observability.md)).

## Red

Migrado a **Gateway API**. Traefik es la *implementación* del Gateway, no solo un
controlador de `Ingress`:

```
            *.albertperez.dev (wildcard DNS) → IP del VPS
                        │
                  ┌─────▼──────┐  Service LoadBalancer
                  │  Traefik   │  (metallb en minikube)
                  └─────┬──────┘
            Gateway "traefik-gateway" (namespace traefik)
             listener websecure :8443 (TLS, cert wildcard)
                        │ HTTPRoute (cada app)
        ┌───────────────┼────────────────┬─────────────┐
        ▼               ▼                 ▼             ▼
     hello          argocd-server     grafana      prometheus
```

- Cada app publica un **`HTTPRoute`** que apunta al listener `websecure` del
  Gateway compartido. El **TLS lo termina el Gateway** con el certificado
  wildcard del entorno (`wildcard-netcup-tls` / `wildcard-minikube-tls`), así
  que las apps solo declaran su `hostname`.
- **Tres excepciones deliberadas** que no usan Gateway API:
  1. **Dashboard de Traefik** → `IngressRoute` nativo (apunta a `api@internal`,
     un servicio interno que Gateway API no puede expresar).
  2. **API gRPC de ArgoCD** (solo netcup) → `Ingress` clásico con scheme `h2c`
     en `argo-api.albertperez.dev` (el CLI `argocd` necesita gRPC).
  3. **Middlewares** de Traefik (basic-auth del dashboard) → CRD `Middleware`.

Por eso Traefik tiene los **tres providers activos** (`kubernetesGateway`,
`kubernetesCRD`, `kubernetesIngress`). Es funcional pero conviene saberlo: hay
tres paradigmas de routing conviviendo. Ver
[assessment.md](assessment.md) para la recomendación de consolidación.

## Estructura de directorios

```
albert-cluster/
├── versions.env              # Fuente de verdad de versiones
├── deploy-local.sh           # Despliegue local idempotente
├── docs/                     # Esta documentación (+ runbooks/)
├── scripts/                  # bootstrap-prod, generate-credentials, new-app
├── tests/smoke.sh            # Smoke tests
├── .github/workflows/        # ci.yaml (main/PR) + dev-ci (rama dev)
└── infra/
    ├── bootstrap/            # CRDs, namespaces (PSS), RBAC, middlewares, sellados
    │   ├── crds/             # Aplicadas con server-side antes que los charts
    │   ├── appset-netcup.yaml    # ApplicationSet de producción (rama main)
    │   └── appset-minikube.yaml  # ApplicationSet de local/CI (rama dev)
    ├── apps/                 # Por app: app.yaml + helmfile + values (+ raíz)
    ├── envs/                 # Overrides por entorno (minikube / netcup)
    └── charts/hello/         # Chart local de ejemplo/plantilla
```

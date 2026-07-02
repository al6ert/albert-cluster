# Aplicaciones

Cada app vive en `infra/apps/<app>/` (release Helmfile) con overrides por entorno
en `infra/envs/<entorno>/<app>-values.yaml`. Versiones en
[`versions.env`](../versions.env).

| App | Chart | Versión | Namespace | Rol | Doc oficial |
|-----|-------|---------|-----------|-----|-------------|
| cert-manager | `jetstack/cert-manager` | `v1.20.2` | `cert-manager` | TLS automático | [cert-manager.io](https://cert-manager.io/docs/) |
| sealed-secrets | `sealed-secrets/sealed-secrets` | `2.18.6` | `kube-system` | Cifrado de secretos | [github](https://github.com/bitnami/sealed-secrets) |
| traefik | `traefik/traefik` | `40.3.0` | `traefik` | Gateway API + ingress | [doc.traefik.io](https://doc.traefik.io/traefik/) |
| argocd | `argo/argo-cd` | `9.5.21` | `argocd` | GitOps | [argo-cd.readthedocs.io](https://argo-cd.readthedocs.io/) |
| prometheus | `prometheus-community/kube-prometheus-stack` | `86.2.2` | `monitoring` | Métricas/dashboards/alertas | [github](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) |
| hello | local `infra/charts/hello` | `0.2.0` | `hello` | App de ejemplo/canario | — |

Repos de charts:
[traefik](https://traefik.github.io/charts) ·
[jetstack](https://charts.jetstack.io) ·
[sealed-secrets](https://bitnami.github.io/sealed-secrets) ·
[argo-helm](https://argoproj.github.io/argo-helm) ·
[prometheus-community](https://prometheus-community.github.io/helm-charts).
Gateway API: [gateway-api.sigs.k8s.io](https://gateway-api.sigs.k8s.io/).

---

## cert-manager

Emite y renueva certificados TLS. En **dev** usa una CA local autofirmada
(`local-ca-issuer`); en **prod** usa Let's Encrypt con challenge **DNS-01** vía
Cloudflare (`letsencrypt-prod`). El certificado wildcard del entorno
(`*.albertperez.dev`) lo monta el listener `websecure` del Gateway de Traefik.
CRDs en `infra/bootstrap/crds/cert-manager-CRDs.yaml`.

## sealed-secrets

Controller en `kube-system` que descifra los `SealedSecret`. Ver
[secrets.md](secrets.md). Se instala antes que el resto porque casi todo depende
de sus secretos.

## traefik

Punto de entrada del cluster (`Service` LoadBalancer) **e implementación de
Gateway API**. Sí, sigue teniendo sentido aunque no escribas objetos `Ingress`:
es el *data plane* que sirve tus `HTTPRoute`. Expone un Gateway compartido
`traefik-gateway`; las apps se enganchan con `HTTPRoute`. Mantiene un
`IngressRoute` nativo para su dashboard (`api@internal`). Ver
[architecture.md](architecture.md#red).

## argocd

El motor GitOps. Se instala en el bootstrap y luego se autogestiona desde Git.
Usa un *config management plugin* para ejecutar Helmfile. Expone la UI por
`HTTPRoute` y, en prod, una API gRPC por `Ingress` h2c (`argo-api.albertperez.dev`)
para el CLI. Contraseña inicial: ver [secrets.md](secrets.md#argocd).

## prometheus (kube-prometheus-stack) — ⚠️ componente pesado

Stack completo: Prometheus + Grafana + Alertmanager + node-exporter +
kube-state-metrics + un montón de CRDs.

**Coste en producción (Netcup, 1 nodo) — ya aligerado:**

| Recurso | Petición |
|---------|----------|
| Disco Prometheus | 20Gi (retención 15d) |
| Disco Grafana | 5Gi |
| Disco Alertmanager | 2Gi |
| RAM Prometheus | 1Gi request / 2Gi limit |
| **Total disco** | **~27Gi** |

Sigue siendo lo que más consume del cluster. Pendiente real: **Alertmanager no
tiene receptores** (Slack/email/Telegram) — configúralos en
`alertmanager.config` o desactívalo; sin receptores no aporta nada.

### Opción A — aligerarlo más / subirlo

Ajusta en `infra/envs/netcup/prometheus-values.yaml`: `retention`, `storageSpec`
y `resources`. Cuando haya apps reales que observar, vuelve a subir retención y
disco según necesidad.

### Opción B — apagarlo de momento (recomendado para arrancar)

Mientras no haya apps propias que observar, puedes no desplegarlo:

1. Comenta la línea de prometheus en `infra/apps/helmfile.yaml`:
   ```yaml
   #  - path: ./prometheus/helmfile.yaml.gotmpl     # wave 3
   ```
2. (Opcional) deja el namespace `monitoring` y el secret `grafana-admin` para
   cuando lo reactives.
3. Commit + push → ArgoCD lo desinstala (prune).

### Alternativas ligeras (cuando vuelvas a querer métricas)

- **VictoriaMetrics** (single-binary, mucho menos RAM/disco que Prometheus).
- **Grafana Agent / Alloy + Grafana Cloud** (free tier): tú solo corres el agente,
  el almacenamiento es gestionado.
- Para logs: **Loki** en modo monolítico, no incluido aún en el cluster.

## hello

App de ejemplo (`hashicorp/http-echo`) que sirve de **plantilla** para añadir
apps y de **canario** para los smoke tests. En producción es opcional: puedes
dejarla como health-check trivial o quitarla cuando tengas apps reales (mismo
método que prometheus opción B). El chart en `infra/charts/hello` es la
referencia de cómo se ve una app bien hecha (securityContext, HTTPRoute,
recursos). Ver [adding-apps.md](adding-apps.md).

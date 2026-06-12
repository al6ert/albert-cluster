# infra/apps — Aplicaciones gestionadas con Helmfile

`helmfile.yaml` es el punto de entrada: define los entornos (`minikube`,
`netcup`) e incluye un sub-helmfile por aplicación. El orden de inclusión
define el orden de despliegue.

```
helmfile.yaml                 # raíz: entornos + orden
├── cert-manager/             # wave 0 — TLS (CRDs en infra/bootstrap/crds)
├── sealed-secrets/           # wave 0 — controller de secretos
├── traefik/                  # wave 1 — Gateway API (traefik-gateway) + dashboard
├── argocd/                   # wave 2 — GitOps + plugin helmfile
├── hello/                    # wave 3 — app de ejemplo (chart local)
└── prometheus/               # wave 3 — kube-prometheus-stack
```

Cada app sigue el mismo patrón:

- `<app>/helmfile.yaml.gotmpl` — release con la versión pineada vía
  `{{ env "<APP>_CHART_VERSION" }}` (fuente de verdad: `versions.env`; en
  ArgoCD las inyecta el plugin desde `infra/bootstrap/argocd-*.yaml`).
- `<app>/values.yaml` — valores base comunes a todos los entornos.
- `../envs/<entorno>/<app>-values.yaml` — overrides por entorno (hostnames,
  certificados wildcard, recursos, réplicas).

## Exposición de servicios

Las apps se exponen con **Gateway API**: `HTTPRoute` → `traefik-gateway`
(namespace `traefik`, listener `websecure` con el certificado wildcard del
entorno). Excepciones deliberadas: el dashboard de Traefik (`IngressRoute`
hacia `api@internal`) y la API gRPC de ArgoCD en producción (`Ingress` con
scheme h2c).

## Render local

```bash
source ../../versions.env
helmfile --environment minikube template   # o netcup
```

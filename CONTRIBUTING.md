# Contribuir a Albert Cluster

Repo GitOps personal (Helmfile + ArgoCD). Documentación completa en
[`docs/`](docs/README.md); esto es el mínimo para trabajar en él.

## Flujo de trabajo

- **Rama `dev`** = cluster local (Minikube). Cada push a `dev` ejecuta el CI de
  desarrollo (bootstrap completo en Minikube + smoke tests).
- **Rama `main`** = producción (Netcup). Un push a `main` dispara `promote-prod`,
  que sincroniza ArgoCD (`cluster-root`). **Nunca** se aplica nada a mano en prod.
- Cambios: rama desde `dev` → PR a `dev` → verde → cuando toque, promociona
  `dev → main`.

## Entorno local

Herramientas: `docker`, `minikube`, `kubectl`, `helm`, `helmfile`, `kubeseal`,
`jq`, `htpasswd`, `openssl` (versiones recomendadas en `versions.env`).

```bash
source versions.env
minikube start --driver=docker --kubernetes-version=${KUBERNETES_VERSION}
./deploy-local.sh      # despliegue completo idempotente
./tests/smoke.sh       # 9 comprobaciones post-deploy
```

Más detalle: [docs/deployment.md](docs/deployment.md).

## Reglas del repo

- **Versiones**: solo en [`versions.env`](versions.env) (el plugin de ArgoCD la
  lee del checkout; no dupliques versiones en otros ficheros). Renovate propone
  actualizaciones según [`renovate.json5`](renovate.json5).
- **Secretos**: jamás en claro. Solo `SealedSecret` generados con
  `scripts/generate-credentials.sh`. Ver [docs/secrets.md](docs/secrets.md).
- **Exposición**: `HTTPRoute` → Gateway `traefik-gateway` (no `Ingress`).
  Cómo añadir una app: [docs/adding-apps.md](docs/adding-apps.md).
- **Apps nuevas**: siempre con `resources` y `securityContext` endurecido
  (referencia: `infra/charts/hello`).
- Antes de commitear: `pre-commit run --all-files` (yamllint es bloqueante
  también en CI).

## Validar sin cluster

```bash
cd infra/apps && source ../../versions.env
helmfile --environment minikube template   # o netcup
```

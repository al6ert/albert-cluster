# Scripts

Resumen de cada script ejecutable del repo: qué hace, cuándo usarlo y veredicto.

| Script | Cuándo | Veredicto |
|--------|--------|-----------|
| [`deploy-local.sh`](#deploy-localsh) | Levantar/actualizar el cluster local | ✅ Núcleo del loop local |
| [`scripts/bootstrap-prod.sh`](#scriptsbootstrap-prodsh) | Una vez, al crear el cluster de prod | ✅ Necesario |
| [`scripts/generate-credentials.sh`](#scriptsgenerate-credentialssh) | Crear/rotar secretos | ✅ Punto único de secretos |
| [`tests/smoke.sh`](#testssmokesh) | Tras desplegar, validar | ✅ Útil |

---

## `deploy-local.sh`

Despliegue **idempotente** completo en minikube. Ver
[deployment.md](deployment.md#desplegar) para el detalle de fases. Es el script
que más usas en el día a día local.

Variables: `DEPLOY_ARGOCD_APPS` (default `true`), `GRAFANA_ADMIN_PASSWORD`
(default `admin` en local).

## `scripts/bootstrap-prod.sh`

Bootstrap **de un solo uso** del cluster de producción: CRDs → namespaces/RBAC/
middlewares → cert-manager → sealed-secrets → traefik → argocd → aplica
`*-sealed.yaml` → crea la Application `cluster-root`. Tras esto, GitOps toma el
control y no vuelves a ejecutarlo salvo recrear el cluster.

## `scripts/generate-credentials.sh`

**Punto único** de generación de credenciales. Crea `Secret`s y los sella con
`kubeseal` contra el cluster del contexto kubectl actual. Ver
[secrets.md](secrets.md).

```bash
./scripts/generate-credentials.sh --component all     # basic-auth + grafana + cloudflare + argocd-redis
./scripts/generate-credentials.sh --component grafana
```

Lee passwords fijos de `.env.local` (`ADMIN_PASSWORD`, `GRAFANA_ADMIN_PASSWORD`,
`CLOUDFLARE_API_TOKEN`, …); sin ellos genera aleatorios (excepto cloudflare, que
exige token real). Respeta `SECRETS_DIR` (deploy-local lo redirige a un temporal
para no pisar los sellados de prod).

## `tests/smoke.sh`

9 pruebas tras el despliegue: pods Running, readiness, namespaces críticos,
servicios, app Hello vía HTTPS, auth del dashboard Traefik, certificados TLS,
SealedSecrets y reinicios excesivos. Hace port-forward a Traefik (`:8443`) y usa
`--resolve` para no depender de DNS. Pensado también para runners de CI.

```bash
WAIT_TIMEOUT=60s ./tests/smoke.sh   # más margen en máquinas lentas
```

---

## Higiene relacionada

- `infra/tmp/` acumula manifiestos renderizados en local (está en `.gitignore`;
  bórralo cuando ocupe demasiado).
- `scripts/deploy.sh` y `temp/` **eliminados** (redundante/anti-GitOps y vacío,
  respectivamente).

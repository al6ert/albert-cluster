# Scripts

Resumen de cada script ejecutable del repo: qué hace, cuándo usarlo y veredicto.

| Script | Cuándo | Veredicto |
|--------|--------|-----------|
| [`deploy-local.sh`](#deploy-localsh) | Levantar/actualizar el cluster local | ✅ Núcleo del loop local |
| [`scripts/bootstrap-prod.sh`](#scriptsbootstrap-prodsh) | Una vez, al crear el cluster de prod | ✅ Necesario |
| [`scripts/generate-credentials.sh`](#scriptsgenerate-credentialssh) | Crear/rotar secretos | ✅ Punto único de secretos |
| [`tests/smoke.sh`](#testssmokesh) | Tras desplegar, validar | ✅ Útil |
| [`scripts/deploy.sh`](#scriptsdeploysh) | — | ⚠️ **Redundante / ambiguo** |

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
./scripts/generate-credentials.sh --component all     # basic-auth + grafana + cloudflare
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

## `scripts/deploy.sh` — ⚠️ redundante

Hace tres cosas que ya están cubiertas en otro sitio:

1. **Validar** manifiestos (`helmfile template` + lint) → ya lo hace la **CI**.
2. **Desplegar con Helmfile directo** en `minikube`/`netcup` → en local lo cubre
   `deploy-local.sh`; en prod **contradice el GitOps puro** (un `helmfile apply`
   manual a netcup se saldría del control de ArgoCD).
3. **Disparar sync de ArgoCD** (`argocd app sync`/kubectl patch) → ya lo hace el
   job `promote-prod` de la CI.

**Recomendación:** elegir una de dos:

- **Eliminarlo** (lo más limpio: nada depende de él).
- O **reducirlo a "render/validate"** local (solo `helmfile template` + lint),
  renombrándolo a algo como `scripts/render.sh`, y quitar las rutas de `apply`
  directo a netcup y de sync.

No tiene referencias desde la CI ni desde otros scripts (solo aparece en el
README como alternativa), así que retirarlo es de bajo riesgo.

---

## Higiene relacionada

- `infra/tmp/` acumula manifiestos renderizados (varios MB). No está trackeado en
  Git pero **no está en `.gitignore`** → añádelo para evitar commits accidentales.
- `temp/` está vacío y sin uso → se puede borrar.
- Ver [assessment.md](assessment.md#limpieza) para la lista completa de limpieza.

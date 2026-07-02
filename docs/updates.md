# Actualizaciones automáticas de apps

## Estado actual

Las versiones viven **solo** en [`versions.env`](../versions.env) (el plugin de
ArgoCD y los scripts la leen del checkout). La configuración de Renovate ya está
en el repo ([`renovate.json5`](../renovate.json5)) y las líneas de `versions.env`
llevan anotaciones `# renovate:`. **Falta un paso manual**: instalar la
[Renovate GitHub App](https://github.com/apps/renovate) en el repo (ver
[Activación](#activación)).

## Objetivo

Automatizar las propuestas de actualización con **reglas de seguridad**, sobre
todo: **no actualizar ninguna app con menos de 7 días de antigüedad** (evita
releases recién publicadas con regresiones), y que un humano apruebe siempre los
cambios **major**.

## Herramienta recomendada: Renovate

Encaja mejor que Dependabot porque entiende **Helm/Helmfile** y permite la regla
`minimumReleaseAge` (la de "<1 semana") y un *manager* por regex para
`versions.env`.

### Reglas que aplicamos

| Regla | Cómo |
|-------|------|
| No actualizar releases con <7 días | `minimumReleaseAge: "7 days"` (global) |
| Majors → revisión manual | PR separada, sin automerge, etiqueta `major` |
| Minor/patch → PR agrupada | Automerge **opcional** solo si pasa CI |
| Parches de seguridad (CVE) | Saltan la espera de 7 días (`vulnerabilityAlerts`) |
| Sólo contra `dev` primero | `baseBranches: ["dev"]` → se prueba en minikube antes de prod |
| Ventana de ejecución | `schedule` (p. ej. lunes por la mañana) |

> El flujo respeta el GitOps: Renovate abre PRs **contra `dev`**, la CI las valida
> en minikube, y solo cuando promocionas `dev → main` llega a producción vía
> ArgoCD. Nunca toca el cluster directamente.

### Config aplicada

La configuración vive en [`renovate.json5`](../renovate.json5) (raíz del repo) y
las dependencias vigiladas se declaran con anotaciones `# renovate:` sobre cada
`export` de [`versions.env`](../versions.env), por ejemplo:

```bash
# renovate: datasource=helm depName=traefik registryUrl=https://traefik.github.io/charts
export TRAEFIK_CHART_VERSION="40.3.0"
```

Sin anotación, Renovate ignora esa línea (así se excluyen a propósito
`*_IMAGE_VERSION`, que van ligadas al appVersion de su chart, y
`GATEWAY_API_VERSION`, que debe coincidir con lo que soporta Traefik).

### Activación

- **GitHub-hosted**: instala la [Renovate GitHub App](https://github.com/apps/renovate)
  en el repo. Cero infra.
- **Self-hosted**: workflow programado con `renovatebot/github-action`.

## ✅ Pre-requisito resuelto: fuente única de versiones

La antigua triplicación (`versions.env` + los dos `argocd-*.yaml`) está
eliminada: el comando `generate` del plugin hace `source versions.env` del
checkout, así que un PR de Renovate que toque `versions.env` cambia lo que
ArgoCD despliega. (Además, la vía antigua ni funcionaba: ArgoCD prefija los
`env:` de la Application como `ARGOCD_ENV_*` y helmfile nunca los veía.)

## Regla de oro operativa

Aunque automatices: **promociona `dev → main` solo después** de ver el cluster de
minikube verde con la versión nueva (CI + `smoke.sh`). La automatización propone;
tú (o la CI) decides cuándo llega a producción.

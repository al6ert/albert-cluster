# Actualizaciones automáticas de apps

## Estado actual

Las versiones se gestionan **a mano** en [`versions.env`](../versions.env) (+ los
dos `infra/bootstrap/argocd-*.yaml`). No hay Renovate ni Dependabot. Esto es
seguro pero implica revisar releases manualmente y es fácil que se quede atrás.

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

### Config propuesta

`renovate.json5` en la raíz del repo:

```json5
{
  $schema: "https://docs.renovatebot.com/renovate-schema.json",
  extends: ["config:recommended", ":dependencyDashboard"],

  // Probar todo contra dev primero (GitOps: dev=minikube, main=producción)
  baseBranches: ["dev"],

  // ── Regla de seguridad principal: nada con menos de 7 días ──
  minimumReleaseAge: "7 days",
  internalChecksFilter: "strict",

  // Ritmo y ruido
  schedule: ["before 9am on monday"],
  prConcurrentLimit: 5,
  labels: ["dependencies"],

  packageRules: [
    // Majors: SIEMPRE manual, PR aislada, sin automerge
    {
      matchUpdateTypes: ["major"],
      automerge: false,
      addLabels: ["major", "needs-review"],
      minimumReleaseAge: "14 days",   // aún más cautela en majors
    },
    // Minor/patch de los charts: agrupar y permitir automerge si CI pasa
    {
      matchManagers: ["helmfile", "helm-values", "regex"],
      matchUpdateTypes: ["minor", "patch"],
      groupName: "charts (minor/patch)",
      automerge: false,   // ponlo en true cuando confíes en la CI
    },
    // Versiones de herramientas/CLI en versions.env
    {
      matchFileNames: ["versions.env"],
      groupName: "tooling versions",
    },
  ],

  // Los CVE saltan la espera de 7 días
  vulnerabilityAlerts: {
    minimumReleaseAge: "0 days",
    addLabels: ["security"],
    schedule: ["at any time"],
  },

  // Manager por regex para versions.env (charts e imágenes pineadas)
  customManagers: [
    {
      customType: "regex",
      managerFilePatterns: ["/versions\\.env$/"],
      matchStrings: [
        // export TRAEFIK_CHART_VERSION="40.3.0" # renovate: datasource=helm depName=traefik registryUrl=https://traefik.github.io/charts
        "#\\s*renovate:\\s*datasource=(?<datasource>\\S+)\\s+depName=(?<depName>\\S+)(\\s+registryUrl=(?<registryUrl>\\S+))?\\s*\\n.*?_VERSION=\"?(?<currentValue>[^\"\\n]+)\"?",
      ],
      versioningTemplate: "{{#if versioning}}{{versioning}}{{else}}semver{{/if}}",
    },
  ],
}
```

Y anota cada línea de `versions.env` que quieras que Renovate vigile, por ejemplo:

```bash
# renovate: datasource=helm depName=traefik registryUrl=https://traefik.github.io/charts
export TRAEFIK_CHART_VERSION="40.3.0"
# renovate: datasource=helm depName=cert-manager registryUrl=https://charts.jetstack.io
export CERT_MANAGER_CHART_VERSION="v1.20.2"
# renovate: datasource=helm depName=argo-cd registryUrl=https://argoproj.github.io/argo-helm
export ARGOCD_CHART_VERSION="9.5.21"
# renovate: datasource=helm depName=sealed-secrets registryUrl=https://bitnami-labs.github.io/sealed-secrets
export SEALED_SECRETS_CHART_VERSION="2.18.6"
# renovate: datasource=helm depName=kube-prometheus-stack registryUrl=https://prometheus-community.github.io/helm-charts
export PROMETHEUS_CHART_VERSION="86.2.2"
```

### Activación

- **GitHub-hosted**: instala la [Renovate GitHub App](https://github.com/apps/renovate)
  en el repo. Cero infra.
- **Self-hosted**: workflow programado con `renovatebot/github-action`.

## ⚠️ Pre-requisito antes de automatizar: arreglar la triplicación de versiones

Hoy la versión de cada chart vive en **tres** sitios (`versions.env` +
`argocd-root.yaml` + `argocd-minikube.yaml`). Si Renovate solo actualiza
`versions.env`, ArgoCD seguiría inyectando la versión vieja en producción.

Opciones (elige una **antes** de activar Renovate):

1. **Que el plugin lea `versions.env`** en vez de tener las versiones inline en
   los `argocd-*.yaml` (elimina la duplicación; ideal).
2. Añadir los `argocd-*.yaml` como `helm-values`/regex managers extra en
   Renovate para que actualice los tres a la vez.

Ver [assessment.md](assessment.md#deuda-técnica) para el contexto.

## Regla de oro operativa

Aunque automatices: **promociona `dev → main` solo después** de ver el cluster de
minikube verde con la versión nueva (CI + `smoke.sh`). La automatización propone;
tú (o la CI) decides cuándo llega a producción.

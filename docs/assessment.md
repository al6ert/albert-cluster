# Rúbrica del estado actual

Evaluación del repo `albert-cluster` desde **múltiples perspectivas**, con nota
**0–10** por dimensión (10 = excelente, 5 = aprobado justo, 0 = ausente).
Contexto: cluster personal, VPS Netcup de un nodo, antes de meter apps propias.
Reevaluada por completo contra el estado real del repo (rama `dev`,
commit `163c6ab`).

## Cuadro resumen

| # | Perspectiva | Nota | Una línea |
|---|-------------|:----:|-----------|
| 1 | Arquitectura GitOps | **8,5** | Diseño limpio, sync-waves claros, CRDs fuera de los charts, render en vivo; resta la Application monolítica. |
| 2 | Mantenibilidad / DRY | **7,5** | Fuente única de versiones efectiva; pero la CI hardcodea `kubernetes-version` y conviven tres paradigmas de routing. |
| 3 | Seguridad (postura) | **6,0** | SealedSecrets + securityContext + TLS en todo; sin NetworkPolicy ni admission control. |
| 4 | Operabilidad Day-2 | **3,0** | Sin backups, sin DR, sin runbooks. Sigue siendo el mayor agujero. |
| 5 | Fiabilidad / HA | **4,5** | Single-node real; réplicas >1 en prod son cosméticas sin más nodos ni PDB. |
| 6 | Observabilidad | **5,0** | Métricas sí; logs no; Alertmanager desplegado pero **sin receptores** (FIXME en los values). |
| 7 | Coste / eficiencia | **6,5** | kube-prometheus-stack ya aligerado (27Gi disco, 1–2Gi RAM, retención 15d); sigue siendo el mayor consumidor. |
| 8 | Preparación para apps propias | **5,0** | Patrón de alta listo y bueno; faltan StorageClass, quotas, NetworkPolicy y confirmar el DNS wildcard. |
| 9 | CI/CD | **7,5** | PR valida en minikube real + smoke; main promociona vía `argocd app sync`; falta gate de Healthy post-sync. |
| 10 | Gestión de dependencias | **7,0** | `renovate.json5` sólido (7 días, majors a 14, CVEs sin espera, baseBranch dev); instalación de la GitHub App sin confirmar. |
| 11 | Developer experience | **8,5** | `deploy-local.sh` idempotente + metallb + nip.io + smoke tests = loop local muy cuidado. |
| 12 | Documentación | **8,0** | Multipágina, precisa en lo esencial; dos desfases menores (`--component all` en scripts.md, paso 4 de deployment.md). |
| 13 | Reproducibilidad | **5,5** | ⬇ **Regresión detectada**: `bootstrap-prod.sh` exige `argocd-redis-sealed.yaml` y no está commiteado → un bootstrap desde cero falla hoy. |
| 14 | Higiene del repo | **8,5** | Árbol limpio; deploy.sh/temp/common/rendered eliminados; solo artefactos locales ignorados. |

**Media: ~6,5/10.** Plataforma bien diseñada con un loop local excelente. Tres
frentes concretos: **backups/DR** (crónico), la **regresión del sellado
`argocd-redis`** (nuevo, bloquea recrear prod) y el **endurecimiento de red/admisión**
antes de apps reales.

---

## Detalle por perspectiva

### 1. Arquitectura GitOps — 8,5
GitOps puro verificado: ArgoCD + CMP Helmfile, sin manifiestos renderizados en
Git, sync-waves por orden de inclusión en `infra/apps/helmfile.yaml`, CRDs
aplicadas server-side desde `infra/bootstrap/crds/`. Los fixes recientes
(timeouts del repo-server vía `argocd-cmd-params-cm`, `source versions.env` en
generate **e init** del CMP, Jobs-hook con ttl=60s eliminados) cierran los
puntos frágiles del plugin. **Resta**: todo cuelga de una `Application`
monolítica; una app rota puede frenar el sync del resto.

### 2. Mantenibilidad / DRY — 7,5
El patrón "una carpeta por app + values por entorno" es excelente y las
versiones tienen fuente única real (`versions.env`, leída por plugin, scripts y
CI). **Lo que baja la nota**: (a) `ci.yaml:65` y `dev-ci.yaml:54` hardcodean
`kubernetes-version: v1.33.1` — cuando Renovate suba `KUBERNETES_VERSION` en
`versions.env`, la CI se quedará atrás en silencio; (b) tres providers de
Traefik activos (Gateway + CRD + Ingress) = tres formas de enrutar conviviendo
(excepciones deliberadas, pero deuda al fin).

### 3. Seguridad — 6,0
**Bien**: SealedSecrets como mecanismo único, permisos mínimos en CI
(`contents: read`), bcrypt en basic-auth, securityContext completo en hello
(runAsNonRoot, drop ALL, readOnlyRootFilesystem, seccomp), TLS en todo con
DNS-01. **Falta** (verificado: cero ocurrencias en `infra/`): `NetworkPolicy`
(red plana), Pod Security Standards / admission control (cualquier chart puede
pedir privilegios), escaneo de imágenes.

### 4. Operabilidad Day-2 — 3,0
**El punto más débil, sin cambios.** No hay backups (ni etcd, ni snapshots de
PV, ni Velero — verificado), no hay plan de DR, no hay runbook de restauración.
En un VPS de un nodo, un fallo de disco = pérdida total. Y la regresión de
`argocd-redis` (ver §13) demuestra que hoy ni siquiera el "recrear desde Git"
funcionaría limpio. Imprescindible antes de datos reales.

### 5. Fiabilidad / HA — 4,5
Un solo nodo: réplicas >1 no dan HA real (mismo nodo, sin PodDisruptionBudget).
No es un fallo si se asume "single-node homelab", pero hay que documentarlo
como tal. Sube ligeramente respecto a la foto anterior porque los syncs largos
ya no se rompen por los Jobs-hook con ttl.

### 6. Observabilidad — 5,0
Prometheus + Grafana + Alertmanager desplegados y expuestos vía Gateway API.
Pero: **Alertmanager sigue sin receptores** (el propio
`infra/envs/netcup/prometheus-values.yaml` lo marca con FIXME — las alertas no
llegan a ningún sitio), **sin agregación de logs** (no hay Loki) y sin
blackbox/uptime checks. Métricas sí; "me entero cuando algo falla", no.

### 7. Coste / eficiencia — 6,5
El aligeramiento prometido está aplicado y verificado en los values de netcup:
retención 15d, 20Gi Prometheus + 5Gi Grafana + 2Gi Alertmanager (~27Gi), RAM
1Gi request / 2Gi limit. Sigue siendo el mayor consumidor del cluster; la
opción de apagarlo hasta tener apps reales sigue sobre la mesa
([apps.md](apps.md#prometheus-kube-prometheus-stack--componente-pesado)).

### 8. Preparación para apps propias — 5,0
El patrón de alta ([adding-apps.md](adding-apps.md)) está listo, es uniforme y
tiene checklist con seguridad por defecto. **Faltan cimientos** (verificado):
`StorageClass`/estrategia de PV para apps con estado, `ResourceQuota` +
`LimitRange` por namespace, `NetworkPolicy`, y confirmar el DNS wildcard
`*.albertperez.dev`.

### 9. CI/CD — 7,5
PR a main → valida manifiestos de ambos entornos + consistencia de namespaces +
minikube real + `deploy-local.sh` + smoke; push a main → `argocd app diff/sync
--prune`; rama dev con su propio CI; concurrencia con cancel-in-progress y
permisos mínimos. **Mejorable**: no hay gate de "esperar a que ArgoCD reporte
Healthy" tras el sync, y el hardcode de `kubernetes-version` (§2) vive aquí.

### 10. Gestión de dependencias — 7,0
`renovate.json5` verificado y bien pensado: `minimumReleaseAge: 7 days` global,
majors a 14 días con etiqueta y sin automerge, kubernetes a 30 días, CVEs sin
espera, PRs solo contra `dev`, dashboard de dependencias. Anotaciones
`# renovate:` en todo `versions.env` (con exclusiones deliberadas razonadas).
**Pendiente**: confirmar que la GitHub App está instalada (no verificable desde
este entorno — si no hay PRs de Renovate ni issue "Dependency Dashboard" en el
repo, no lo está).

### 11. Developer experience — 8,5
`deploy-local.sh` idempotente con secretos dummy autogenerados (incluido el de
`argocd-redis`), metallb automático (sin `minikube tunnel` con sudo), nip.io
(sin tocar hosts), smoke tests con 9 comprobaciones y `WAIT_TIMEOUT`
configurable. Levantar el cluster en local es de lo más cuidado del repo.

### 12. Documentación — 8,0
`docs/` multipágina, con índice, precisa en lo esencial (versiones de apps.md =
`versions.env`, fases de deploy = código real, rúbrica viva). **Dos desfases
menores detectados en esta reevaluación**: (a) `scripts.md` dice que
`--component all` = basic-auth + grafana + cloudflare, pero desde el fix de
redis también incluye `argocd-redis`; (b) el paso 4 de `deployment.md` no
menciona el dummy de `argocd-redis` que `deploy-local.sh` sí genera.

### 13. Reproducibilidad — 5,5 ⬇
Versiones pineadas + GitOps hacen el cluster reconstruible **en teoría**. Pero:
**regresión nueva** — al desactivar el Job `redis-secret-init` del chart de
ArgoCD, `bootstrap-prod.sh` pasó a exigir `argocd-redis-sealed.yaml` entre los
sellados obligatorios, y ese archivo **no está en
`infra/bootstrap/secrets/`** ni en su `kustomization.yaml` (solo hay
basic-auth, grafana y cloudflare). Un bootstrap de producción desde cero
fallaría hoy. A eso se suman los restos ya conocidos: token de Cloudflare
manual, sellados ligados al cluster y DNS fuera del repo.

### 14. Higiene del repo — 8,5
`scripts/deploy.sh`, `temp/`, `infra/envs/common/` e `infra/rendered/`
eliminados; `infra/tmp/` en `.gitignore`; árbol de trabajo limpio; scripts
restantes todos justificados ([scripts.md](scripts.md)).

---

## Respuestas directas (vigentes de la evaluación anterior)

- **¿Sobra alguna app?** No como error de diseño. `prometheus` sigue siendo
  demasiado pesado para un VPS de un nodo sin apps que observar (apagarlo o
  aligerarlo más: [apps.md](apps.md)); `hello` es plantilla/canario, opcional
  en prod.
- **¿Tiene sentido Traefik sin objetos `Ingress`?** Sí: Traefik es la
  **implementación** de Gateway API — quien sirve los `HTTPRoute` y termina el
  TLS. Lo "legacy" son las tres excepciones deliberadas (dashboard, gRPC de
  ArgoCD, middlewares), documentadas en [architecture.md](architecture.md#red).
- **¿Qué falta antes de apps propias?** Backups/DR, StorageClass, NetworkPolicy,
  quotas, DNS wildcard confirmado, receptores de Alertmanager — ver backlog.

---

## Backlog priorizado

### 🔴 Antes de producción / apps propias
- [ ] **Regenerar y commitear `argocd-redis-sealed.yaml`** (sellado contra prod)
      y añadirlo a `infra/bootstrap/secrets/kustomization.yaml` — sin él,
      `bootstrap-prod.sh` falla y el Redis de ArgoCD se queda sin secret
      gestionado por GitOps.
- [ ] **Backups y DR**: Velero (o snapshots del proveedor) + un restore probado.
- [ ] **Estrategia de almacenamiento**: `StorageClass` por defecto y qué apps
      llevan PV.
- [ ] **Confirmar DNS wildcard** `*.albertperez.dev` → IP del VPS.
- [ ] **Confirmar instalación de la Renovate GitHub App** (la config ya está).
- [x] Triplicación de versiones resuelta (`source versions.env` en el plugin).
- [x] Monitorización aligerada (retención 15d, ~27Gi, RAM a la mitad).

### 🟠 Endurecimiento
- [ ] `NetworkPolicy` por namespace (default-deny + reglas explícitas).
- [ ] Admission control: Pod Security Standards (built-in) o Kyverno.
- [ ] `ResourceQuota` + `LimitRange` por namespace de app.
- [ ] Alertmanager con receptor real (Slack/email/Telegram) o desactivarlo.
- [ ] `PodDisruptionBudget` donde aplique.

### 🟡 Calidad / limpieza
- [ ] **Des-hardcodear `kubernetes-version`** en `ci.yaml:65` y `dev-ci.yaml:54`
      (leerla de `versions.env` o aceptar el drift documentándolo).
- [ ] Actualizar `scripts.md` (`--component all` incluye `argocd-redis`) y el
      paso 4 de `deployment.md` (dummy de argocd-redis).
- [ ] Gate de "ArgoCD Healthy" en `promote-prod` tras el sync.
- [ ] Evaluar `ApplicationSet`/Applications por app vs la monolítica.
- [ ] A futuro: consolidar routing hacia solo Gateway API.
- [x] `scripts/deploy.sh`, `temp/`, `infra/envs/common/`, `infra/rendered/`
      eliminados; `.gitignore` cubre `infra/tmp/`.
- [x] `CONTRIBUTING.md` reescrito acorde al flujo real.
- [x] Jobs-hook con ttl=60s eliminados (syncs largos ya no se rompen).

### Nota sobre la deuda de versiones (RESUELTA)
Los `env:` de la Application llegaban al plugin prefijados como `ARGOCD_ENV_*`,
así que los pins nunca aplicaban vía ArgoCD. Resuelto: el CMP hace
`source versions.env` del checkout (en generate **y** en init) — fuente única,
pins efectivos, Renovate desbloqueado.

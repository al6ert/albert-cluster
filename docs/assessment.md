# Rúbrica del estado actual

Evaluación del repo `albert-cluster` desde **múltiples perspectivas**. Notas de
**A (excelente)** a **F (ausente)**. Contexto: cluster personal, VPS Netcup de un
nodo, antes de meter apps propias.

## Cuadro resumen

| # | Perspectiva | Nota | Una línea |
|---|-------------|:----:|-----------|
| 1 | Arquitectura GitOps | **A-** | Diseño limpio, sync-waves claros, CRDs fuera de los charts, render en vivo. |
| 2 | Mantenibilidad / DRY | **B+** | Buen patrón por app y fuente única de versiones; queda la convivencia de paradigmas de routing. |
| 3 | Seguridad (postura) | **B-** | SealedSecrets + RBAC mínimo + securityContext en hello; faltan NetworkPolicy y admission control. |
| 4 | Operabilidad Day-2 | **D+** | Sin backups, sin DR, sin runbooks. El mayor agujero. |
| 5 | Fiabilidad / HA | **C** | Single-node real; "replicas: 2" en prod es cosmético. |
| 6 | Observabilidad | **C+** | Métricas sí (pesadas), logs no, alertas sin receptores. |
| 7 | Coste / eficiencia | **B-** | kube-prometheus-stack aligerado (~27Gi + 1-2Gi RAM); sigue siendo el mayor consumidor. |
| 8 | Preparación para apps propias | **C** | Patrón de alta listo; faltan storage, quotas, network policy, DNS confirmado. |
| 9 | CI/CD | **B+** | PR valida en minikube, main promociona vía ArgoCD, concurrencia controlada. |
| 10 | Gestión de dependencias | **B** | Fuente única + Renovate configurado (falta instalar la App); regla de 7 días. |
| 11 | Developer experience | **A-** | `deploy-local.sh` idempotente + nip.io + smoke tests = loop local muy bueno. |
| 12 | Documentación | **A-** | Multipágina y al día; CONTRIBUTING reescrito. |
| 13 | Reproducibilidad | **B** | Versiones pineadas y GitOps; resta el secreto cloudflare manual y DNS externo. |
| 14 | Higiene del repo | **A-** | deploy.sh/temp/common/rendered eliminados; solo quedan logs locales ignorados. |

**Media ponderada: ~C+/B-.** Una base de plataforma sólida y bien pensada, con
dos debilidades claras: **operabilidad day-2 (backups/DR)** y **deuda de DRY en
versiones**. Nada de esto bloquea seguir, pero conviene cerrarlo antes de
producción real.

---

## Detalle por perspectiva

### 1. Arquitectura GitOps — A-
GitOps puro de verdad: ArgoCD + plugin Helmfile, sin manifiestos renderizados en
Git, sync-waves por orden de inclusión, CRDs aplicadas server-side fuera de los
charts. Separación dev/main → minikube/netcup limpia. **Resta**: todo cuelga de
una sola `Application` monolítica; una app rota puede frenar el sync del resto.

### 2. Mantenibilidad / DRY — B+
El patrón "una carpeta por app + values por entorno" es excelente y repetible,
y las versiones tienen **fuente única** (`versions.env`, que el plugin lee del
checkout). **Lo que baja la nota**: hay **tres providers de Traefik** activos
(Gateway + CRD + Ingress) = tres formas de enrutar conviviendo.

### 3. Seguridad — B-
**Bien**: SealedSecrets como mecanismo único, RBAC mínimo en CI (`contents:
read`), bcrypt para basic-auth, securityContext endurecido en el chart hello,
TLS en todo. **Falta**: `NetworkPolicy` (red plana, todo pod habla con todo),
admission control / Pod Security Standards (cualquier chart puede pedir
privilegios), escaneo de imágenes. Ver backlog.

### 4. Operabilidad Day-2 — D+
**El punto más débil.** No hay backups (ni etcd, ni snapshots de PV, ni Velero),
no hay plan de DR, no hay runbook de restauración. En un VPS de un nodo, un fallo
de disco = pérdida total. Imprescindible antes de datos reales.

### 5. Fiabilidad / HA — C
Un solo nodo: `replicaCount: 2` en hello de netcup no da HA real (mismo nodo, sin
PodDisruptionBudget). No es un fallo si asumes "single-node homelab", pero hay
que **documentarlo como tal** y no venderlo como HA.

### 6. Observabilidad — C+
Prometheus + Grafana presentes. Pero: **sin agregación de logs** (no hay Loki),
**Alertmanager sin receptores** configurados (no avisa a ningún lado), sin
blackbox/uptime checks. Métricas sí, "me entero cuando algo falla" no.

### 7. Coste / eficiencia — C
`kube-prometheus-stack` pide ~70Gi de disco y 2-4Gi de RAM solo Prometheus: es,
de lejos, el mayor consumidor del cluster en un VPS de un nodo. Ver
[apps.md](apps.md#prometheus-kube-prometheus-stack--componente-pesado) para
aligerar o apagar.

### 8. Preparación para apps propias — C
El patrón de despliegue está listo y es bueno. **Faltan cimientos**: definir
`StorageClass`/estrategia de PV para apps con estado, `ResourceQuota`/`LimitRange`
por namespace, `NetworkPolicy`, y **confirmar el DNS wildcard** `*.albertperez.dev`.

### 9. CI/CD — B+
PR → valida en minikube real + smoke tests; main → `argocd app diff/sync`;
concurrencia con cancel-in-progress; permisos mínimos. Muy correcto. Mejorable:
no hay gate de "esperar a que ArgoCD reporte Healthy" tras el sync.

### 10. Gestión de dependencias — B
Fuente única en `versions.env` con anotaciones Renovate y `renovate.json5`
(regla de 7 días, majors manuales, CVEs sin espera). Falta instalar la GitHub
App para que empiece a abrir PRs. Detalle en [updates.md](updates.md).

### 11. Developer experience — A-
`deploy-local.sh` idempotente, metallb automático (sin `minikube tunnel` con
sudo), `nip.io` (sin tocar hosts), smoke tests legibles. Levantar el cluster en
local es de los puntos más cuidados.

### 12. Documentación — A-
`docs/` multipágina, al día y con la rúbrica viva; `CONTRIBUTING.md` reescrito
acorde al flujo real (dev→minikube, main→prod).

### 13. Reproducibilidad — B
Versiones pineadas + GitOps hacen el cluster reconstruible. Resta: el token de
Cloudflare es manual y los SealedSecrets van ligados al cluster (recrearlo exige
re-sellar todo), y el DNS vive fuera del repo.

### 14. Higiene del repo — A-
`scripts/deploy.sh`, `temp/`, `infra/envs/common/` e `infra/rendered/`
eliminados; `infra/tmp/` cubierto por `.gitignore`. Solo quedan artefactos
locales ya ignorados (`.ci-logs/`, `.dev-ci-logs/`).

---

## Respuestas directas a tus preguntas

### ¿Sobra alguna app?
- **No, ninguna "sobra" como error de diseño.** cert-manager, sealed-secrets,
  traefik y argocd son plataforma core, todos justificados.
- **`prometheus` (kube-prometheus-stack)**: no sobra conceptualmente, pero es
  **demasiado pesado para arrancar** en un VPS de un nodo sin apps que observar.
  Recomendación: **apagarlo hasta tener apps reales** o aligerarlo mucho. Cómo, en
  [apps.md](apps.md#prometheus-kube-prometheus-stack--componente-pesado).
- **`hello`**: es ejemplo/canario. Útil como plantilla y para smoke tests;
  opcional en producción. Mantenlo en dev, quítalo de prod si quieres.

### ¿Tiene sentido Traefik si no voy a usar Ingress?
**Sí, rotundamente.** Confusión habitual: "Ingress" (el objeto `Ingress` de K8s)
≠ "ingress controller" (el proxy que enruta el tráfico). Has migrado a **Gateway
API**, y Traefik es **la implementación** de ese Gateway: es quien realmente
sirve tus `HTTPRoute` y termina el TLS. Sin él (u otra implementación como Cilium
/ Envoy Gateway / NGINX Gateway Fabric) tus apps no serían accesibles desde
fuera. No es opcional y **no hay solापamiento** con otro controlador. Lo único
"legacy" es que mantiene activo el provider de `Ingress` para la API gRPC de
ArgoCD: excepción deliberada y mínima.

### ¿Qué me falta antes de instalar apps propias?
Por prioridad (ver backlog abajo): **backups/DR**, **StorageClass + estrategia de
PV**, **NetworkPolicy**, **ResourceQuota/LimitRange por namespace**, **confirmar
DNS wildcard**, **alertas con receptores reales**, y decidir si pasas de la
`Application` monolítica a `ApplicationSet`/Applications por app.

### ¿Qué me sobra / es redundante?
1. ~~`scripts/deploy.sh`~~ — **eliminado** (solapaba CI + deploy-local + sync).
2. ~~Versiones triplicadas~~ — **resuelto** con fuente única en `versions.env`.
3. ~~`temp/`, `infra/envs/common/`, `infra/rendered/`~~ — **eliminados**.
4. **Tres providers de Traefik** — consolidar a futuro hacia solo Gateway API
   (único punto que sigue en pie).

---

## Backlog priorizado

### 🔴 Antes de producción / apps propias
- [ ] **Backups y DR**: Velero (o snapshots del proveedor) + un restore probado.
- [ ] **Estrategia de almacenamiento**: definir `StorageClass` por defecto y qué
      apps llevan PV.
- [x] **Triplicación de versiones resuelta**: el plugin hace `source versions.env`
      del checkout (fuente única). Ver [updates.md](updates.md).
- [ ] **Confirmar DNS wildcard** `*.albertperez.dev` → IP del VPS.
- [x] **Monitorización aligerada**: retención 15d, ~27Gi total, RAM a la mitad.
      Pendiente decidir receptores de Alertmanager.

### 🟠 Endurecimiento
- [ ] `NetworkPolicy` por namespace (default-deny + reglas explícitas).
- [ ] Admission control: Pod Security Standards (built-in) o Kyverno.
- [ ] `ResourceQuota` + `LimitRange` por namespace de app.
- [ ] Alertmanager con receptor real (Slack/email) o quitarlo.
- [ ] `PodDisruptionBudget` donde aplique.

### 🟡 Calidad / limpieza
- [x] `scripts/deploy.sh` eliminado.
- [x] `.gitignore` ya cubre `infra/tmp/`; `temp/`, `infra/envs/common/` e
      `infra/rendered/` eliminados.
- [x] `CONTRIBUTING.md` reescrito acorde a la realidad.
- [x] Renovate configurado (`renovate.json5` + anotaciones en `versions.env`).
      Falta instalar la GitHub App en el repo.
- [ ] Evaluar `ApplicationSet`/Applications por app vs la `Application` monolítica.
- [ ] A futuro: consolidar routing hacia solo Gateway API.

### <a id="deuda-técnica"></a>Nota sobre la deuda técnica de versiones (RESUELTA)
La triple fuente de versión era peor que deuda: los `env:` de la Application
llegan al plugin prefijados como `ARGOCD_ENV_*`, así que los pins **nunca
aplicaban** vía ArgoCD (renderizaba "latest"). Resuelto haciendo que el comando
`generate` del plugin haga `source versions.env` del checkout: fuente única,
pins efectivos y Renovate desbloqueado.

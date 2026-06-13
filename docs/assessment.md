# Rúbrica del estado actual

Evaluación del repo `albert-cluster` desde **múltiples perspectivas**. Notas de
**A (excelente)** a **F (ausente)**. Contexto: cluster personal, VPS Netcup de un
nodo, antes de meter apps propias.

## Cuadro resumen

| # | Perspectiva | Nota | Una línea |
|---|-------------|:----:|-----------|
| 1 | Arquitectura GitOps | **A-** | Diseño limpio, sync-waves claros, CRDs fuera de los charts, render en vivo. |
| 2 | Mantenibilidad / DRY | **C+** | Buen patrón por app, pero versiones triplicadas y dos paradigmas de routing. |
| 3 | Seguridad (postura) | **B-** | SealedSecrets + RBAC mínimo + securityContext en hello; faltan NetworkPolicy y admission control. |
| 4 | Operabilidad Day-2 | **D+** | Sin backups, sin DR, sin runbooks. El mayor agujero. |
| 5 | Fiabilidad / HA | **C** | Single-node real; "replicas: 2" en prod es cosmético. |
| 6 | Observabilidad | **C+** | Métricas sí (pesadas), logs no, alertas sin receptores. |
| 7 | Coste / eficiencia | **C** | kube-prometheus-stack se come el VPS (~70Gi + 2-4Gi RAM). |
| 8 | Preparación para apps propias | **C** | Patrón de alta listo; faltan storage, quotas, network policy, DNS confirmado. |
| 9 | CI/CD | **B+** | PR valida en minikube, main promociona vía ArgoCD, concurrencia controlada. |
| 10 | Gestión de dependencias | **C** | Centralizado en versions.env pero 100% manual y triplicado. |
| 11 | Developer experience | **A-** | `deploy-local.sh` idempotente + nip.io + smoke tests = loop local muy bueno. |
| 12 | Documentación | **B** (tras esta tanda) | Antes monolítica en README; ahora multipágina. CONTRIBUTING está desactualizado. |
| 13 | Reproducibilidad | **B** | Versiones pineadas y GitOps; resta el secreto cloudflare manual y DNS externo. |
| 14 | Higiene del repo | **B-** | `infra/tmp/` sin gitignore, `temp/` vacío, restos de logs de CI. |

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

### 2. Mantenibilidad / DRY — C+
El patrón "una carpeta por app + values por entorno" es excelente y repetible.
**Lo que baja la nota**: la versión de cada chart está **en tres sitios**
(`versions.env`, `argocd-root.yaml`, `argocd-minikube.yaml`) → riesgo de drift.
Y hay **tres providers de Traefik** activos (Gateway + CRD + Ingress) = tres
formas de enrutar conviviendo.

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

### 10. Gestión de dependencias — C
Centralización en `versions.env` es buena idea, pero 100% manual y **triplicada**.
Sin Renovate/Dependabot. Plan en [updates.md](updates.md).

### 11. Developer experience — A-
`deploy-local.sh` idempotente, metallb automático (sin `minikube tunnel` con
sudo), `nip.io` (sin tocar hosts), smoke tests legibles. Levantar el cluster en
local es de los puntos más cuidados.

### 12. Documentación — B (tras esta tanda)
Antes: todo en un README de 300 líneas. Ahora: `docs/` multipágina. **Pendiente**:
`CONTRIBUTING.md` está genérico/desactualizado (habla de "kind", "unit tests",
"API documentation" que no aplican).

### 13. Reproducibilidad — B
Versiones pineadas + GitOps hacen el cluster reconstruible. Resta: el token de
Cloudflare es manual y los SealedSecrets van ligados al cluster (recrearlo exige
re-sellar todo), y el DNS vive fuera del repo.

### 14. Higiene del repo — B-
`infra/tmp/` (varios MB de YAML renderizado) **no está en `.gitignore`** (aunque
hoy no esté trackeado). `temp/` vacío. Restos `.ci-logs/`/`.dev-ci-logs/` (sí
ignorados). Limpieza menor pendiente.

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
1. **`scripts/deploy.sh`** — solapa CI + deploy-local + sync de ArgoCD, y su rama
   "helmfile apply directo a netcup" contradice el GitOps. Quitar o reducir a
   render. Ver [scripts.md](scripts.md#scriptsdeploysh--redundante).
2. **Versiones triplicadas** — la redundancia más real y peligrosa.
3. **`infra/tmp/`** y **`temp/`** — basura/artefactos.
4. **Tres providers de Traefik** — consolidar a futuro hacia solo Gateway API.

---

## Backlog priorizado

### 🔴 Antes de producción / apps propias
- [ ] **Backups y DR**: Velero (o snapshots del proveedor) + un restore probado.
- [ ] **Estrategia de almacenamiento**: definir `StorageClass` por defecto y qué
      apps llevan PV.
- [ ] **Resolver la triplicación de versiones** (que el plugin lea `versions.env`).
      Bloqueante para automatizar updates. Ver [updates.md](updates.md).
- [ ] **Confirmar DNS wildcard** `*.albertperez.dev` → IP del VPS.
- [ ] **Decidir monitorización**: apagar o aligerar kube-prometheus-stack.

### 🟠 Endurecimiento
- [ ] `NetworkPolicy` por namespace (default-deny + reglas explícitas).
- [ ] Admission control: Pod Security Standards (built-in) o Kyverno.
- [ ] `ResourceQuota` + `LimitRange` por namespace de app.
- [ ] Alertmanager con receptor real (Slack/email) o quitarlo.
- [ ] `PodDisruptionBudget` donde aplique.

### 🟡 Calidad / limpieza
- [ ] `scripts/deploy.sh`: eliminar o reducir a render.
- [ ] `.gitignore`: añadir `infra/tmp/`; borrar `temp/`.
- [ ] Reescribir `CONTRIBUTING.md` acorde a la realidad (sin kind/unit tests).
- [ ] Activar Renovate con la config de [updates.md](updates.md).
- [ ] Evaluar `ApplicationSet`/Applications por app vs la `Application` monolítica.
- [ ] A futuro: consolidar routing hacia solo Gateway API.

### <a id="limpieza"></a>Limpieza inmediata (bajo riesgo)
```bash
# Añadir a .gitignore:  infra/tmp/
rmdir temp 2>/dev/null || true
```

### <a id="deuda-técnica"></a>Nota sobre la deuda técnica de versiones
La triple fuente de versión (`versions.env` + `argocd-root.yaml` +
`argocd-minikube.yaml`) es la deuda con más impacto: rompe DRY, invita al drift
prod/local y **bloquea** la automatización de updates. Atacarla primero
desbloquea varios puntos del backlog a la vez.

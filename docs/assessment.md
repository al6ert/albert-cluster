# Rúbrica del estado actual

Evaluación del repo `albert-cluster` desde **múltiples perspectivas**, con nota
**0–10** por dimensión (10 = excelente, 5 = aprobado justo, 0 = ausente).
Contexto: cluster personal, VPS Netcup de un nodo, antes de meter apps propias.

**Reevaluada el 2026-07-03 (tarde)** tras ejecutar el plan de corrección de
debilidades: modelo per-app (ApplicationSet), backups+DR, observabilidad
externa, endurecimiento y DX de alta de apps. Varias dimensiones tienen dos
lecturas: la nota **actual** y la nota al completar los
[pasos manuales pendientes](#pendiente-manual).

## Cuadro resumen

| # | Perspectiva | Nota | → al cerrar pendientes | Una línea |
|---|-------------|:----:|:----:|-----------|
| 1 | Arquitectura GitOps | **9,0** | | ApplicationSet per-app (salud/sync granular, alta por carpeta), CMP robusto (walk-up, sin races), CRDs en bootstrap. |
| 2 | Mantenibilidad / DRY | **8,5** | | Pins efectivos en TODAS las vías (plugin, scripts y ahora también CI); queda la convivencia de 3 providers de Traefik. |
| 3 | Seguridad (postura) | **7,5** | 8,0 | PSS enforce por namespace (verificado), quotas+LimitRange, netpol declaradas; el CNI (flannel) no las aplica aún. |
| 4 | Operabilidad Day-2 | **5,5** | 8,5 | Velero+runbook+escrow diseñados y commiteados, pero NO operativos: falta bucket R2, escrow real y drill. Certs kubeadm caducados = incidente activo. |
| 5 | Fiabilidad / HA | **5,5** | 6,5 | Single-node documentado como asunción; retry en syncs; sin Jobs-hook frágiles. El incidente de certs demuestra el riesgo pendiente. |
| 6 | Observabilidad | **5,5** | 8,5 | Modelo Alloy→Grafana Cloud listo en el repo (alertas+synthetic fuera del nodo); inactivo hasta crear la cuenta. Mientras, kps sigue sin receptores. |
| 7 | Coste / eficiencia | **7,0** | 8,0 | VPS holgado (8vCPU/16GB/1TB al 3%); la retirada de kps (~27Gi+2Gi RAM) está preparada y gateada. |
| 8 | Preparación para apps propias | **8,0** | | new-app.sh + PSS restricted por defecto + quotas + patrón netpol + checklist; falta solo estrategia de storage para la primera app con estado. |
| 9 | CI/CD | **8,5** | | Validación con pins reales (antes renderizaba latest), guard de doble registro, promote por label con gate de salud 600s. |
| 10 | Gestión de dependencias | **7,5** | 8,5 | 4 charts nuevos anotados para Renovate; regla 7 días respetada al elegir versiones; App de GitHub sin confirmar. |
| 11 | Developer experience | **9,0** | | Alta de app = 1 script + push; loop local idempotente; nip.io; smoke tests. |
| 12 | Documentación | **9,0** | | observability.md y runbook DR nuevos, adding-apps.md reescrito, entorno prod verificado y documentado, rúbrica viva. |
| 13 | Reproducibilidad | **7,0** | 9,0 | Runbook completo + doble backup de la clave sealed-secrets diseñado; sigue faltando el sellado de argocd-redis (prod inaccesible) y el drill. |
| 14 | Higiene del repo | **8,5** | | CHANGELOG-plantilla eliminado; árbol limpio; scripts todos justificados. |

**Media: ~7,5/10 (≈8,3 al cerrar los pendientes manuales).** El salto viene de
convertir debilidades estructurales (monolito, sin backups, sin runbooks, CI
sin pins) en mecanismos verificados. Lo que queda es **operacional**, no de
diseño: 6 pasos manuales listados abajo.

---

## Qué cambió respecto a la evaluación de la mañana

| Debilidad (nota anterior) | Qué se hizo |
|---------------------------|-------------|
| Application monolítica (arq. 8,5) | **ApplicationSet per-app** con git files generator: alta por carpeta, salud granular, retry. Validado en minikube con cutover real + adopción de recursos. Tres bugs del CMP encontrados y corregidos por el camino: path fijo de versions.env, OOM con renders concurrentes, y **race del output-dir compartido** (apps sincronizaban manifests ajenos). |
| Day-2 3,0: sin backups/DR | **Velero → R2** (clave sealed-secrets 90d + config del cluster 30d + node-agent para PVs futuros), **runbook DR completo** con drill reproducible en minikube, escrow documentado de la clave. |
| Observabilidad 5,0: alertas a ninguna parte | **Alloy → Grafana Cloud** (solo netcup): métricas+logs+eventos fuera del VPS, alertas Telegram y synthetic checks que sobreviven a la caída del nodo. kube-prometheus-stack queda en retirada gateada. |
| Sin PSS/netpol/quotas (seg. 6,0) | **PSS enforce** en todos los namespaces (verificado: pod privilegiado rechazado, cero violaciones existentes), app **policies** (netpol+quota+LimitRange), NetworkPolicy de referencia en el chart hello. flannel no aplica netpol → decisión de CNI pendiente. |
| CI hardcode + pins no aplicados | `versions.env` completo exportado al job (la validación renderizaba **sin pins** = latest — bug real heredado), guard app.yaml↔helmfile raíz, namespaces por subconjunto, promote-prod por label con `app wait --health`. |
| Reproducibilidad 5,5: argocd-redis sin sellar | Pendiente de prod (ver abajo): el API server tiene los **certificados kubeadm caducados desde 2026-06-29** — incidente descubierto en la fase 0. Los workloads siguen sirviendo. |

## <a id="pendiente-manual"></a>Pendiente manual (en orden)

1. 🔴 **Renovar los certificados de kubeadm** (el API de prod es inaccesible):
   `ssh netcup` → backup `/etc/kubernetes` → `kubeadm certs renew all` →
   reiniciar plano de control → refrescar kubeconfig local. Comandos exactos
   en el [runbook](runbooks/disaster-recovery.md).
2. 🔴 **Escrow de la clave sealed-secrets** al gestor de contraseñas
   ([secrets.md](secrets.md)).
3. 🔴 **Sellar y commitear `argocd-redis`** con el password vivo
   (`ARGOCD_REDIS_PASSWORD=$(kubectl get secret argocd-redis -n argocd -o jsonpath='{.data.auth}' | base64 -d) ./scripts/generate-credentials.sh --component argocd-redis`).
4. 🟠 **Cuenta Grafana Cloud** + URLs reales + `--component grafana-cloud` +
   contact point Telegram + synthetic checks ([observability.md](observability.md)).
5. 🟠 **Bucket R2** + token S3 scoped + `--component velero`.
6. 🟠 **Cutover de producción** al ApplicationSet (procedimiento probado en
   minikube: [deployment.md](deployment.md#cutover-al-modelo-per-app-una-sola-vez-por-cluster)),
   promocionar `dev → main`, y tras validar Grafana Cloud: retirar
   kube-prometheus-stack (PR preparado conceptualmente, ver apps.md).
7. 🟡 Confirmar la **Renovate GitHub App**; ejecutar y anotar el **drill de DR**;
   decidir **CNI con enforcement** (Cilium/Calico) si se quiere red aplicada.

## Backlog técnico restante

- [ ] Estrategia de `StorageClass`/PV antes de la primera app con estado.
- [ ] Migrar CNI a Cilium/Calico para que las NetworkPolicy se apliquen (hoy declarativas).
- [ ] Consolidar routing hacia solo Gateway API (3 providers de Traefik).
- [ ] Subir argocd/traefik de `baseline` a `restricted` si warn/audit no chillan.
- [ ] Vigilancia de expiración de certs kubeadm (métrica o recordatorio anual; ver runbook).
- [ ] deploy-local.sh: devolvió exit 0 con un fallo de helm dentro (endurecer manejo de errores).

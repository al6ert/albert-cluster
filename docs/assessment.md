# Rúbrica del estado actual

Evaluación del repo `albert-cluster` desde **múltiples perspectivas**, con nota
**0–10** por dimensión (10 = excelente, 5 = aprobado justo, 0 = ausente).
Contexto: cluster personal, VPS Netcup de un nodo, antes de meter apps propias.

**Reevaluada el 2026-07-03 (tarde)** tras ejecutar el plan de corrección de
debilidades: modelo per-app (ApplicationSet), backups+DR, observabilidad
externa, endurecimiento y DX de alta de apps. Varias dimensiones tienen dos
lecturas: la nota **actual** y la nota al completar los
[pasos manuales pendientes](#pendiente-manual).

**Revisión del 2026-07-06:** auditoría específica de la
[cadena de actualización automática](#cadena-actualizaciones). Hallazgo
principal: la App de Renovate **no está instalada** (verificado contra la API
de GitHub: cero PRs y cero issues del bot en toda la historia del repo), así
que toda la cadena de mantenimiento automático está diseñada pero **apagada**.
La dimensión 10 baja de 7,5 a 5,5 para reflejar realidad, no diseño.

## Cuadro resumen

| # | Perspectiva | Nota | → al cerrar pendientes | Una línea |
|---|-------------|:----:|:----:|-----------|
| 1 | Arquitectura GitOps | **9,0** | | ApplicationSet per-app (salud/sync granular, alta por carpeta), CMP robusto (walk-up, sin races), CRDs en bootstrap. |
| 2 | Mantenibilidad / DRY | **8,5** | | Pins efectivos en TODAS las vías (plugin, scripts y ahora también CI); queda la convivencia de 3 providers de Traefik. |
| 3 | Seguridad (postura) | **7,5** | 8,0 | PSS enforce por namespace (verificado), quotas+LimitRange, netpol declaradas; el CNI (flannel) no las aplica aún. |
| 4 | Operabilidad Day-2 | **6,0** | 8,5 | Certs renovados y runbook probado en el incidente real; Velero listo pero inactivo hasta el bucket R2; drill pendiente. |
| 5 | Fiabilidad / HA | **6,5** | | Single-node documentado; incidente de certs resuelto (válidos hasta 2027) y GitOps de prod descongelado tras 6 meses. |
| 6 | Observabilidad | **5,5** | 8,5 | Modelo Alloy→Grafana Cloud listo en el repo (alertas+synthetic fuera del nodo); inactivo hasta crear la cuenta. Mientras, kps sigue sin receptores. |
| 7 | Coste / eficiencia | **7,0** | 8,0 | VPS holgado (8vCPU/16GB/1TB al 3%); la retirada de kps (~27Gi+2Gi RAM) está preparada y gateada. |
| 8 | Preparación para apps propias | **8,0** | | new-app.sh + PSS restricted por defecto + quotas + patrón netpol + checklist; falta solo estrategia de storage para la primera app con estado. |
| 9 | CI/CD | **8,5** | | Validación con pins reales (antes renderizaba latest), guard de doble registro, promote por label con gate de salud 600s. |
| 10 | Gestión de dependencias | **5,5** | 8,5 | Config de Renovate excelente (7d mínimo, majors 14d manuales, CVE sin espera) pero la App **no está instalada**: 0 PRs del bot en la historia del repo. Diseño ✓, motor apagado. Ver [análisis](#cadena-actualizaciones). |
| 11 | Developer experience | **9,0** | | Alta de app = 1 script + push; loop local idempotente; nip.io; smoke tests. |
| 12 | Documentación | **9,0** | | observability.md y runbook DR nuevos, adding-apps.md reescrito, entorno prod verificado y documentado, rúbrica viva. |
| 13 | Reproducibilidad | **8,5** | 9,0 | argocd-redis sellado y commiteado, claves exportadas, runbook completo, prod reconstruible y al día con los pins. Falta el drill. |
| 14 | Higiene del repo | **8,5** | | CHANGELOG-plantilla eliminado; árbol limpio; scripts todos justificados. |

**Media: ~7,6/10 (≈8,3 al activar observabilidad, backups y Renovate).** El
salto de junio vino de convertir debilidades estructurales (monolito, sin
backups, sin runbooks, CI sin pins) en mecanismos verificados. Lo que queda es
**operacional**, no de diseño — pero la revisión del 2026-07-06 confirma que
lo operacional pendiente no es cosmético: sin la App de Renovate el repo tiene
exactamente el mismo modo de fallo que congeló prod 6 meses (nadie se entera
de que nada avanza).

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

## <a id="cadena-actualizaciones"></a>¿Se mantienen solas las apps que instale? (auditoría 2026-07-06)

Pregunta concreta: *si añado una app hoy, ¿recibirá actualizaciones de forma
automática, con salvaguardas tipo "nada inestable ni con menos de N días"?*
Respuesta corta: **hoy no; con ~1 hora de trabajo, casi.** Sub-rúbrica por
eslabón de la cadena:

| Eslabón | Nota | Estado real |
|---------|:----:|-------------|
| Detección de versiones nuevas | **2,0** | renovate.json5 impecable, pero la App de GitHub no está instalada: **cero PRs del bot, nunca**. Verificado el 2026-07-06 contra la API (`author:app/renovate` → 0 resultados). Nada detecta nada. |
| Salvaguardas de estabilidad (diseño) | **9,0** | `minimumReleaseAge: 7 days` (más estricto que los 3 días que pedíamos como mínimo), majors 14 días + PR aislada + sin automerge, `internalChecksFilter: strict`, y `config:recommended` ya ignora pre-releases. Mejor que la petición original. |
| Cobertura: charts upstream | **8,5** | Todos los charts de versions.env anotados; `new-app.sh` añade la anotación automáticamente al hacer scaffold. El eslabón que mejor está. |
| Cobertura: imágenes ligadas al chart | **4,0** | `TRAEFIK_IMAGE_VERSION`, `CERT_MANAGER_IMAGE_VERSION`, `VELERO_AWS_PLUGIN_VERSION` y `GATEWAY_API_VERSION` van *a propósito* sin anotación ("actualizar a la vez que el chart") pero **ningún guard de CI comprueba esa alineación**: Renovate subirá el chart, un humano hará merge y el pin de imagen/CRD se quedará atrás en silencio. |
| Cobertura: apps propias (charts locales) | **3,0** | Un chart `--local` queda 100 % fuera del circuito: versión de chart a mano y, peor, las **imágenes de contenedor en values.yaml no tienen manager** de Renovate. Justo "las apps que instale" propias son las menos cubiertas. |
| Validación antes de aplicar | **8,5** | Toda PR de versión pasa dev-ci con pins reales y minikube; el bug histórico de renderizar `latest` está corregido. |
| Automatismo del merge | **5,0** | `automerge: false` en todo: cada actualización, por trivial que sea, espera a un humano. Es lo prudente para arrancar, pero significa que hoy el sistema es *semi*-automático por diseño. |
| Llegada a producción | **5,0** | Promote dev→main por label con gate de salud 600 s: sólido pero manual y **sin alarma de divergencia**. Si el humano desaparece, dev avanza y prod se congela — el modo de fallo exacto de los 6 meses perdidos, ahora un escalón más arriba. |
| Parche urgente (CVE) | **4,0** | `vulnerabilityAlerts` con espera 0 existe, pero se alimenta de los security advisories de GitHub, que **no cubren charts de Helm detectados por regex manager**: en la práctica ese carril rápido casi nunca saltará para lo que corre en el cluster. |
| El cluster en sí | **3,5** | Renovate solo mueve el `KUBERNETES_VERSION` de CI/minikube; el kubeadm de netcup y los paquetes del VPS no tienen ni automatismo ni recordatorio (salvo los certs, con runbook tras el incidente). |

**Nota del eslabón más débil: 2,0 — y en una cadena manda el eslabón más
débil.** La configuración es de las mejores piezas del repo; el problema es
que nada la ejecuta.

### Plan de cierre recomendado (en orden)

1. **Instalar la App de Renovate** (github.com/apps/renovate → repo
   `al6ert/albert-cluster`). 5 minutos; enciende toda la cadena y el
   Dependency Dashboard hace visible lo que queda fuera.
2. Dejar 2–3 ciclos semanales con `automerge: false` y, cuando la CI haya
   demostrado que filtra bien, **activar automerge solo para el grupo
   minor/patch** de versions.env (el comentario del json5 ya lo prevé). Ahí la
   respuesta a "¿se mantienen solas?" pasa a ser "sí" para dev.
3. Decidir la cadencia de prod: o rutina fija (promocionar cada lunes si dev
   lleva N días verde) o una **alerta de divergencia dev↔main > 14 días**
   cuando exista Grafana Cloud. Sin esto, el automatismo se para en dev.
4. **Guard de alineación imagen↔chart** en CI (comparar `*_IMAGE_VERSION` con
   el `appVersion` del chart renderizado; lo mismo para `GATEWAY_API_VERSION`
   vs el go.mod de Traefik) o, más simple, anotar también las imágenes y
   agruparlas con su chart en una misma PR.
5. Para apps propias: **regex manager para imágenes docker en values.yaml**
   (datasource=docker) y pin por digest si el registro lo permite. Añadir la
   anotación al scaffold de `new-app.sh --local`.

Con 1–3 hechas, la dimensión 10 sube sola a ~8,5; con 4–5, a ~9.

## <a id="pendiente-manual"></a>Estado del cierre (actualizado tras el cutover de prod, 2026-07-03 tarde)

**Hecho el 2026-07-03 (tarde):**
- ✅ Certificados de kubeadm renovados (válidos hasta 2027-07-03; backup de
  `/etc/kubernetes` en `/root/k8s-pki-backup-*.tar.gz` del VPS) y kubeconfig
  local refrescado.
- ✅ **Hallazgo mayor durante el cutover: el GitOps de prod llevaba ~6 meses
  congelado** — el ConfigMap del plugin CMP nunca existió en prod (la trampa
  conocida de extraObjects) y el repo-server arrastraba un rollout atascado
  desde hacía 169 días; todos los charts seguían en las versiones del
  bootstrap (dic-2025) y prometheus/Gateway API nunca llegaron a desplegarse.
- ✅ Cutover de producción completado: argo-cd 8.1.3→9.5.21 por helm (única
  intervención manual), resto vía ApplicationSet — **9/9 Applications
  Synced+Healthy**, traefik 37→40.3 con Gateway API servido en vivo
  (hello/argo 200 vía HTTPRoute, wildcard Ready), cert-manager 1.20.2,
  hello endurecido (PSS restricted cumplido), policies aplicadas.
- ✅ `argocd-redis-sealed.yaml` sellado con el password vivo y commiteado.
- ✅ Claves del controller sealed-secrets exportadas (8 claves) a
  `~/sealed-secrets-keys-netcup-20260703.yaml` — **falta guardarlas en el
  gestor de contraseñas y borrar el archivo**.
- ✅ Flags `MONITORING_ENABLED`/`VELERO_ENABLED`/`PROMETHEUS_ENABLED` (=false
  en prod): las apps sin configuración externa quedan Synced-vacías.

**Pendiente (usuario):**
1. 🟠 Guardar `~/sealed-secrets-keys-netcup-20260703.yaml` en el gestor de
   contraseñas y borrar el archivo local.
2. 🟠 **Cuenta Grafana Cloud** + URLs reales + `--component grafana-cloud` +
   `MONITORING_ENABLED=true` + contact point Telegram + synthetic checks
   ([observability.md](observability.md)). Hasta entonces prod está sin
   observabilidad (como llevaba 6 meses, pero ahora a sabiendas).
3. 🟠 **Bucket R2** + token S3 scoped + `--component velero` +
   `VELERO_ENABLED=true`.
4. 🟠 **Renovate GitHub App**: instalación lanzada el 2026-07-06 (repo
   albert-cluster, only-select) — falta el toque final de passkey (sudo mode
   de GitHub). Verificar después que aparece el Dependency Dashboard.
5. 🟠 **Langfuse en prod**: sellar `langfuse-secrets` contra netcup
   (`./scripts/generate-credentials.sh --component langfuse` con contexto
   netcup; variables opcionales en `.env`), commit + apply del sealed,
   `LANGFUSE_ENABLED=true` y promocionar. Tras el primer login, poner
   `langfuse.features.signUpDisabled: true` (instancia pública).
6. 🟡 Ejecutar y anotar el **drill de DR**; decidir **CNI con enforcement**
   (Cilium/Calico); decidir la retirada definitiva de kube-prometheus-stack
   (hoy solo corre en minikube).

## Backlog técnico restante

- [x] Estrategia de `StorageClass`/PV — **hecho 2026-07-06**: OpenEBS LocalPV
      hostpath (app `storage`, default class en netcup, Retain). Primera app
      con estado: langfuse.
- [ ] Migrar CNI a Cilium/Calico para que las NetworkPolicy se apliquen (hoy declarativas).
- [ ] Consolidar routing hacia solo Gateway API (3 providers de Traefik).
- [ ] Subir argocd/traefik de `baseline` a `restricted` si warn/audit no chillan.
- [ ] Vigilancia de expiración de certs kubeadm (métrica o recordatorio anual; ver runbook).
- [ ] deploy-local.sh: devolvió exit 0 con un fallo de helm dentro (endurecer manejo de errores).
- [ ] Guard de CI imagen↔chart: comparar `*_IMAGE_VERSION` con el `appVersion` renderizado (y `GATEWAY_API_VERSION` con lo que soporta Traefik).
- [ ] Regex manager de Renovate para imágenes docker en values.yaml (cubre apps propias); añadirlo al scaffold `--local` de new-app.sh.
- [ ] Automerge de minor/patch cuando la CI acumule 2–3 ciclos de Renovate en verde.
- [ ] Alarma de divergencia dev↔main (>14 días sin promocionar) al activar Grafana Cloud.
- [ ] Limpiar los exports `*_ACTION_VERSION` de versions.env: los workflows hardcodean `@v4`/`@v0.0.15`, esos exports no se usan (el manager github-actions de Renovate ya cubre los workflows directamente).

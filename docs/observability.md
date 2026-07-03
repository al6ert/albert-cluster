# Observabilidad

Modelo: **Grafana Alloy dentro del cluster → Grafana Cloud (free tier) fuera**.
En un cluster de un solo nodo, el alerting self-hosted muere con el nodo; por
eso métricas, logs, alertas y uptime checks viven **fuera del VPS**.

```
 Cluster netcup                          Grafana Cloud (free)
 ┌──────────────────────────┐           ┌──────────────────────────┐
 │ app "monitoring"         │  remote   │ Mimir (métricas, 14d)    │
 │  Alloy metrics (2 pods)  │  write    │ Loki  (logs, 14d)        │
 │  Alloy logs (DaemonSet)  │ ────────► │ Grafana + dashboards     │
 │  Alloy singleton (events)│   push    │ Alerting → Telegram      │
 │  kube-state-metrics      │           │ Synthetic Monitoring ────┼─► checks
 │  node-exporter           │           └──────────────────────────┘   externos
 └──────────────────────────┘                                          (nodo caído)
```

La app vive en `infra/apps/monitoring/` (chart `grafana/k8s-monitoring`) y
**solo se instala en netcup** (`installed:` en su helmfile). En minikube el
loop local se valida con `tests/smoke.sh`.

## Puesta en marcha (manual, una vez)

1. Crear cuenta free en [grafana.com](https://grafana.com) → crear stack.
2. Del stack, anotar: URL de *Prometheus remote write*, URL de *Loki push*,
   los dos usuarios numéricos y un **Cloud Access Policy token** con scopes
   `metrics:write` + `logs:write`.
3. Sustituir las URLs `REPLACE-ME` en `infra/envs/netcup/monitoring-values.yaml`.
4. En `.env.local`: `GRAFANA_CLOUD_PROM_USER`, `GRAFANA_CLOUD_LOKI_USER`,
   `GRAFANA_CLOUD_TOKEN`. Con kubectl apuntando a netcup:
   ```bash
   ./scripts/generate-credentials.sh --component grafana-cloud
   git add infra/bootstrap/secrets/grafana-cloud-credentials-sealed.yaml && git commit
   ```
5. Promocionar a main. Si las URLs siguen en placeholder, Alloy queda
   Degraded y el gate de CI frena el deploy (fallo ruidoso).

## Alertas mínimas (configurar en Grafana Cloud → Alerting)

Contact point recomendado: **Telegram** (bot + chat id). Reglas:

| Alerta | Expresión (orientativa) |
|--------|--------------------------|
| Nodo caído / cluster mudo | `absent(up{cluster="netcup"})` o alerta *no data* sobre cualquier métrica del cluster |
| Disco >80% | `node_filesystem_avail_bytes / node_filesystem_size_bytes < 0.2` |
| Pod en CrashLoop | `kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} > 0` |
| Certificado a <15d | `certmanager_certificate_expiration_timestamp_seconds - time() < 15*86400` |
| App de ArgoCD degradada | `argocd_app_info{health_status!="Healthy"} == 1` (sostenida 15m) |

**Synthetic Monitoring** (checks externos HTTPS, detectan el nodo caído
aunque todo lo demás muera con él): `https://hello.albertperez.dev` y
`https://argo.albertperez.dev`.

⚠️ Añadir también un check/alerta para la **expiración de los certificados de
kubeadm** (caducan al año; ya provocaron un incidente el 2026-06-29). El
synthetic check del API server no es posible desde Grafana Cloud (puerto
6443); la vía práctica es la métrica `apiserver_client_certificate_expiration_seconds`
o un recordatorio de calendario + `kubeadm certs check-expiration` (ver
[runbook](runbooks/disaster-recovery.md)).

## Scrape de apps propias

`annotationAutodiscovery` está activo: cualquier pod/service con

```yaml
annotations:
  k8s.grafana.io/scrape: "true"
  k8s.grafana.io/metrics.portNumber: "8080"   # si no es el único puerto
```

entra solo en Prometheus. No hay que tocar la app monitoring.

## Historia

Hasta 2026-07 el cluster corría `kube-prometheus-stack` completo (~27Gi disco,
1-2Gi RAM) con Alertmanager **sin receptores**: métricas que nadie miraba y
alertas que no llegaban a ningún sitio. Se sustituyó por este modelo
(decisión A1 del plan; el chart antiguo sigue en git si se quisiera volver).

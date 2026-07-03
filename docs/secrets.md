# Secretos y contraseñas

Un **único mecanismo**: [Sealed Secrets](https://sealed-secrets.netlify.app/).
Un único script para generarlos: [`scripts/generate-credentials.sh`](scripts.md#scriptsgenerate-credentialssh).

## Cómo funciona

1. Escribes un `Secret` normal en claro (en memoria/temporal).
2. `kubeseal` lo cifra con la **clave pública del controller** del cluster →
   produce un `SealedSecret`.
3. El `SealedSecret` (`*-sealed.yaml`) **se commitea**: solo el controller del
   cluster contra el que se selló tiene la clave privada para descifrarlo.
4. En el cluster, el controller lo convierte en un `Secret` real.

> ⚠️ **Los `SealedSecret` están ligados al cluster.** Un sellado contra
> producción **no** se abre en minikube y viceversa. Por eso `deploy-local.sh`
> regenera secretos dummy locales en vez de usar los del repo.

## Secretos del cluster

| Componente | Secret (namespace) | Lo consume | Generar con |
|------------|--------------------|------------|-------------|
| Basic-auth dashboard | `admin-basic-auth` (`admin`) | Middleware basic-auth de Traefik | `--component basic-auth` |
| Grafana admin | `grafana-admin` (`monitoring`) | `grafana.admin.existingSecret` (kube-prometheus-stack, en retirada) | `--component grafana` |
| Cloudflare API token | `cloudflare-api-token` (`cert-manager`) | ClusterIssuer `letsencrypt-prod` (DNS-01) | `--component cloudflare` |
| Redis de ArgoCD | `argocd-redis` (`argocd`) | Auth del Redis (el Job `redis-secret-init` del chart está desactivado: su ttl de 60s hacía fallar syncs largos) | `--component argocd-redis` |
| Grafana Cloud | `grafana-cloud-credentials` (`monitoring`) | Alloy (app `monitoring`): remote write de métricas/logs | `--component grafana-cloud` |
| R2 backups | `velero-r2-credentials` (`velero`) | Velero (BackupStorageLocation en R2) | `--component velero` |

Archivos sellados: `infra/bootstrap/secrets/*-sealed.yaml`.

## ⚠️ Escrow de la clave del controller (hazlo AHORA, no en el desastre)

La clave privada del controller de sealed-secrets es **el único secreto que no
puede regenerarse**: sin ella, todos los `*-sealed.yaml` del repo son
irrecuperables. Doble respaldo:

1. **Manual** (tras el bootstrap y tras cada rotación de clave, ~30 días):
   ```bash
   kubectl get secret -n kube-system \
     -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-keys.yaml
   ```
   Guárdalo cifrado en el gestor de contraseñas (exporta TODAS las claves del
   label, no solo la activa) y borra el fichero local.
2. **Automático**: el schedule `sealed-secrets-key` de Velero lo sube a R2 a
   diario (retención 90d).

Restauración: [runbook DR](runbooks/disaster-recovery.md) — la clave se aplica
**antes** de que el controller arranque.

## `.env.local` (no versionado)

Único fichero con los valores en claro que `generate-credentials.sh` sella.
El esquema canónico (con placeholders) vive versionado en
[`.env.local.example`](../.env.local.example): cópialo a `.env.local` y
rellénalo. Si una variable falta, su componente genera un valor aleatorio
(salvo los tokens externos, obligatorios donde se indica).

> **Un solo fichero para los dos entornos.** No hay un `.env` para prod y otro
> para local: el cluster contra el que se sella lo decide el **contexto de
> kubectl**, no el fichero (los `SealedSecret` van atados a su cluster). Por eso
> `deploy-local.sh` sella los dummy locales en un dir temporal con este mismo
> `.env.local`.

```bash
# .env.local  (en .gitignore; esquema completo en .env.local.example)
TRAEFIK_LOGIN=admin          # login del dashboard de Traefik (basic-auth)
TRAEFIK_PASSWORD=...          # su contraseña
CLOUDFLARE_API_TOKEN=...      # token DNS de Cloudflare (obligatorio para prod)
GRAFANA_ADMIN_PASSWORD=...    # admin de Grafana (kube-prometheus-stack; minikube)
GRAFANA_CLOUD_PROM_USER=...   # id numérico del stack (métricas)   ┐ app monitoring
GRAFANA_CLOUD_LOKI_USER=...   # id numérico del stack (logs)       │ (solo si
GRAFANA_CLOUD_TOKEN=...       # Cloud Access Policy token          ┘  MONITORING_ENABLED)
R2_ACCESS_KEY_ID=...          # token S3 de R2 scoped al bucket    ┐ velero
R2_SECRET_ACCESS_KEY=...      #                                    ┘ (solo si VELERO_ENABLED)
```

## Rotar un secreto

```bash
# kubectl apuntando al cluster correcto (¡el sellado va ligado a él!)
# 1. Actualiza el valor en .env.local (o deja que se genere aleatorio)
./scripts/generate-credentials.sh --component grafana   # o all / basic-auth / cloudflare
# 2. Commitea el nuevo sellado
git add infra/bootstrap/secrets/grafana-admin-sealed.yaml
git commit -m 'chore: rotate grafana admin secret'
# 3. En prod, push → ArgoCD lo aplica. En local, kubectl apply -f ...
```

## <a id="argocd"></a>Password de ArgoCD admin

ArgoCD genera su propia contraseña inicial (no pasa por SealedSecrets):

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Cámbiala tras el primer login. En local, `deploy-local.sh` la imprime al final.

## Reglas

- **Nunca** commitees secretos en claro. `.gitignore` ya bloquea `*-secret.yaml`,
  `.env*`, `*.htpasswd`, `*.key`, `*.pem`.
- Los `*-sealed.yaml` **sí** se commitean: es seguro y es lo que hace GitOps
  reproducible.
- Si recreas el cluster de producción, **regenera todos los sellados** contra el
  cluster nuevo (la clave privada del controller cambia).

## Mejoras futuras

Para secretos de apps propias que rotan a menudo (credenciales de BD, tokens de
API de terceros), valora migrar a
[external-secrets](https://external-secrets.io/) + un backend real (Vault,
Bitwarden, SSM). SealedSecrets es ideal para bootstrap pero es estático. Ver
[assessment.md](assessment.md).

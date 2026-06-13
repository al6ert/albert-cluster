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
| Grafana admin | `grafana-admin` (`monitoring`) | `grafana.admin.existingSecret` | `--component grafana` |
| Cloudflare API token | `cloudflare-api-token` (`cert-manager`) | ClusterIssuer `letsencrypt-prod` (DNS-01) | `--component cloudflare` |

Archivos sellados: `infra/bootstrap/secrets/*-sealed.yaml`.

## `.env.local` (no versionado)

Passwords fijos opcionales. Si no existen, se generan aleatorios (salvo
Cloudflare, que **exige** token real):

```bash
# .env.local  (en .gitignore)
ADMIN_PASSWORD=...            # usuario admin del basic-auth
ARGO_PASSWORD=...             # usuario argo del basic-auth (si se usa)
GRAFANA_ADMIN_PASSWORD=...    # admin de Grafana
CLOUDFLARE_API_TOKEN=...      # token DNS de Cloudflare (obligatorio para prod)
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

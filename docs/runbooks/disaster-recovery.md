# Runbook: Disaster Recovery (reconstruir producción desde cero)

Escenario: el VPS de Netcup se pierde (disco roto, borrado, migración).
Objetivo: cluster reconstruido y sirviendo con **Git como fuente de verdad**.

**Tiempo estimado**: 45–90 min. **Prerequisito crítico**: tener la clave del
controller de sealed-secrets (paso 3). Sin ella, ningún `*-sealed.yaml` del
repo se puede dessellar y hay que regenerar TODOS los secretos.

## 0. Estado que NO está en Git (lo que de verdad hay que restaurar)

| Estado | Dónde se respalda |
|--------|-------------------|
| **Clave privada sealed-secrets** | Escrow manual en gestor de contraseñas + backup Velero diario `sealed-secrets-key` (R2, 90d) |
| Recursos generados en runtime (certs emitidos, secrets dessellados) | Backup Velero diario `cluster-config` (R2, 30d) — casi todo es regenerable |
| PVs de apps con estado | Velero node-agent (kopia) cuando existan |
| DNS wildcard `*.albertperez.dev` → IP | Cloudflare (fuera del cluster; actualizar IP si cambia) |

## 1. Recrear el VPS e instalar Kubernetes

Entorno verificado 2026-07 (ver [architecture.md](../architecture.md)):
Ubuntu 22.04 LTS, **kubeadm v1.33.x**, containerd, flannel, nodo único.

```bash
# En el VPS nuevo (como root) — versiones pineadas a las del cluster original
apt-get update && apt-get install -y containerd apt-transport-https
# kubeadm/kubelet/kubectl v1.33.x desde pkgs.k8s.io (repo v1.33)
kubeadm init --pod-network-cidr=10.244.0.0/16
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
kubectl taint nodes --all node-role.kubernetes.io/control-plane-  # nodo único
```

Copiar `/etc/kubernetes/admin.conf` al kubeconfig local como contexto `netcup`.

> ⚠️ **kubeadm emite los certificados del plano de control a 1 AÑO.**
> Ya provocó un incidente (2026-06-29: API inaccesible, workloads vivos).
> Tras cada `kubeadm init`: apuntar renovación en el calendario o confiar en
> `kubeadm upgrade` anual (los renueva). Renovación manual:
> ```bash
> ssh netcup 'tar czf /root/k8s-pki-$(date +%F).tar.gz /etc/kubernetes && kubeadm certs renew all'
> # reiniciar plano de control (kubelet recrea los static pods):
> ssh netcup 'crictl pods --name "kube-apiserver|kube-controller-manager|kube-scheduler|etcd" -q | xargs -r -n1 crictl stopp'
> # refrescar el kubeconfig local con el admin.conf renovado
> ```

## 2. Restaurar la clave de sealed-secrets — ANTES de instalar el controller

Si el controller arranca sin la clave vieja, genera una nueva y los sellados
del repo no abrirán. Orden estricto.

**Vía A (primaria) — escrow del gestor de contraseñas:**
```bash
kubectl apply -f sealed-secrets-keys.yaml   # el export guardado en el gestor
```

**Vía B — backup de Velero en R2 (sin cluster, con aws cli):**
```bash
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...   # token R2
aws s3 ls s3://albert-cluster-backups/backups/ \
  --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com
aws s3 sync s3://albert-cluster-backups/backups/sealed-secrets-key-<FECHA>/ ./restore \
  --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com
# los Secrets están en el tar.gz de recursos; extraer y aplicar los
# kube-system/secrets con label sealedsecrets.bitnami.com/sealed-secrets-key
```

**Si el controller ya arrancó** (creó clave nueva): aplicar igualmente las
claves viejas y reiniciar el controller — mantiene ambas y dessella con la
antigua.

## 3. Bootstrap del cluster

```bash
# kubectl apuntando al cluster nuevo
./scripts/bootstrap-prod.sh
```

Aplica CRDs (server-side) → namespaces/RBAC/middlewares → cert-manager →
sealed-secrets (ya con la clave restaurada) → traefik → argocd → sellados →
ApplicationSet `cluster-apps`. ArgoCD reconcilia el resto desde `main`.

## 4. Verificación

```bash
kubectl get applications -n argocd -l cluster=netcup   # todo Synced/Healthy
kubectl get certificate -A                             # wildcard emitido (LE puede tardar ~2 min)
curl -sI https://hello.albertperez.dev | head -1       # 200
curl -sI https://argo.albertperez.dev | head -1        # 200
velero backup get                                      # BSL Available
```

Si la IP del VPS cambió: actualizar el registro wildcard en Cloudflare.

## 5. Restaurar PVs (cuando haya apps con estado)

```bash
velero restore create --from-backup <backup> --include-namespaces <ns-app>
```

---

## Drill en minikube (probar el procedimiento sin tocar prod)

Valida el paso crítico (2): que una clave exportada dessella tras recrear el
cluster.

```bash
# 1. En el minikube actual: sellar un secret de prueba y exportar la clave
kubectl create secret generic dr-test --from-literal=ok=yes -n default \
  --dry-run=client -o yaml | kubeseal --format yaml > /tmp/dr-test-sealed.yaml
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > /tmp/ss-keys.yaml

# 2. Destruir y recrear
minikube delete && source versions.env && \
  minikube start --driver=docker --kubernetes-version=${KUBERNETES_VERSION}

# 3. Restaurar la clave ANTES del controller, luego desplegar
kubectl create namespace kube-system --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f /tmp/ss-keys.yaml
./deploy-local.sh

# 4. El secret de prueba debe dessellar
kubectl apply -f /tmp/dr-test-sealed.yaml
kubectl get secret dr-test -n default -o jsonpath='{.data.ok}' | base64 -d  # → yes
```

| Drill ejecutado | Resultado |
|-----------------|-----------|
| _(pendiente)_ | — |

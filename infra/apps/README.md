# Aplicaciones ArgoCD

Este directorio contiene las aplicaciones de ArgoCD que gestionan el despliegue de los componentes del cluster.

## Estructura Optimizada

```
infra/apps/
├── base/
│   ├── kustomization.yaml         # Base (netcup/producción)
│   ├── traefik/
│   │   ├── argocd-application.yaml
│   │   └── ingressroutes.yaml     # IngressRoutes consolidados
│   └── hello/
│       └── argocd-application.yaml
└── overlays/
    └── minikube/
        ├── kustomization.yaml     # Overlay para minikube
        ├── patches-traefik.yaml   # Patch para traefik
        ├── patches-hello.yaml     # Patch para hello
        └── patches-traefik-dashboard.yaml # Patch para IngressRoutes
```

## Gestión de Entornos

### Enfoque Kustomize con Overlays

Utilizamos **Kustomize** para manejar las diferencias entre entornos de manera elegante:

- **Una sola ArgoCD Application** por componente
- **Base** para producción (netcup)
- **Overlay** para minikube (desarrollo)
- **Valores de Helm** separados en `infra/envs/`
- **IngressRoutes consolidados** en un solo archivo

### Dos Formas de Deploy en Local

#### 1. Helmfile (Desarrollo Rápido)
```bash
# Deploy completo con Helmfile
helmfile -f infra/apps/helmfile.yaml apply

# Deploy específico
helmfile -f infra/apps/helmfile.yaml apply --selector name=traefik
helmfile -f infra/apps/helmfile.yaml apply --selector name=hello
```

#### 2. ArgoCD + Kustomize (Pruebas de GitOps)
```bash
# Deploy completo con Kustomize
kustomize build infra/apps/overlays/minikube | kubectl apply -f -

# O usando el script
./scripts/deploy.sh minikube
```

### Entornos Soportados

#### Minikube (Desarrollo Local)
```bash
# Deploy usando Kustomize
kustomize build infra/apps/overlays/minikube | kubectl apply -f -

# O usando el script
./scripts/deploy.sh minikube
```

**Configuración:**
- Dominio: `127.0.0.1.nip.io`
- Sin TLS
- Configuración ligera

#### Netcup (Producción)
```bash
# Deploy usando Kustomize
kubectl apply -k infra/apps/base/

# O usando el script
./scripts/deploy.sh netcup
```

**Configuración:**
- Dominio: `albertperez.dev`
- TLS con Let's Encrypt
- Configuración completa

## Patches de Kustomize

### Minikube (`overlays/minikube/patches-traefik.yaml`)

```yaml
- op: replace
  path: /spec/source/helm/valueFiles/1
  value: ../../../envs/minikube/traefik-values.yaml
- op: replace
  path: /spec/source/helm/extraObjects/0/spec/routes/0/match
  value: Host(`traefik.127.0.0.1.nip.io`)
- op: replace
  path: /spec/source/helm/extraObjects/0/spec/entryPoints
  value:
    - web
    - websecure
```

### Minikube (`overlays/minikube/patches-hello.yaml`)

```yaml
- op: replace
  path: /spec/source/helm/valueFiles/1
  value: ../../../envs/minikube/hello-values.yaml
```

### Netcup (`base/kustomization.yaml`)

No requiere patches ya que las ArgoCD Applications están configuradas por defecto para producción.

## Ventajas de este Enfoque

1. **DRY (Don't Repeat Yourself)**: Una sola ArgoCD Application por componente
2. **Mantenibilidad**: Cambios centralizados en un lugar
3. **Flexibilidad**: Fácil agregar nuevos entornos
4. **Consistencia**: Misma estructura para todos los entornos
5. **Claridad**: Separación clara entre configuración base y específica
6. **Simplicidad**: Estructura estándar de Kustomize

## Comandos Útiles

```bash
# Ver estado de las aplicaciones
kubectl get applications -n argocd

# Ver logs de Traefik
kubectl logs -n traefik -l app.kubernetes.io/name=traefik

# Verificar sincronización
kubectl describe application traefik -n argocd

# Aplicar cambios
kustomize build infra/apps/overlays/minikube | kubectl apply -f -
```

## Troubleshooting

### Problemas Comunes

1. **Aplicación no sincroniza**: Verificar que ArgoCD esté funcionando
2. **Valores no se aplican**: Verificar paths en valueFiles
3. **Dominios no resuelven**: Verificar configuración DNS

### Logs Útiles

```bash
# Logs de ArgoCD
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# Logs de Traefik
kubectl logs -n traefik -l app.kubernetes.io/name=traefik

# Estado de las aplicaciones
kubectl get applications -n argocd -o yaml
```

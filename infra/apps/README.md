# Configuración de Aplicaciones - Estrategia Híbrida GitOps

## Resumen de la Configuración

Esta configuración implementa una **estrategia híbrida** que combina:
- **Helmfile** para desarrollo local (minikube)
- **ArgoCD** para producción (netcup)

## Estructura de Archivos

```
infra/
├── apps/
│   ├── traefik/
│   │   ├── argocd-application.yaml    # ArgoCD Application para Traefik
│   │   └── values.yaml                # Values base para Traefik
│   ├── hello/
│   │   └── argocd-application.yaml    # ArgoCD Application para Hello
│   ├── helmfile.yaml                  # Helmfile para desarrollo local
│   └── kustomization.yaml             # Kustomization para apps
├── envs/
│   ├── minikube/                      # Valores para desarrollo local
│   │   ├── traefik-values.yaml
│   │   └── hello-values.yaml
│   └── netcup/                        # Valores para producción
│       ├── traefik-values.yaml
│       └── hello-values.yaml
└── charts/
    └── hello/                         # Chart local de Hello
        └── values.yaml
```

## Configuración por Entorno

### Desarrollo Local (Minikube)
- **Herramienta**: Helmfile
- **Comando**: `helmfile -e minikube apply`
- **Dominio**: `127.0.0.1.nip.io`
- **TLS**: Staging Let's Encrypt

### Producción (Netcup)
- **Herramienta**: ArgoCD
- **Configuración**: Automated sync
- **Dominio**: `albertperez.dev`
- **TLS**: Producción Let's Encrypt

## Problemas Críticos Corregidos

### ✅ Estructura de Overrides
- **Antes**: Archivos de netcup eran ArgoCD Applications
- **Después**: Archivos de netcup son values.yaml correctos

### ✅ Externalización de Values
- **Antes**: Values hardcodeados en ArgoCD Applications
- **Después**: Uso de `valueFiles` para cargar archivos externos

### ✅ Configuración de certResolver
- **Antes**: `certResolver: ""` vacío
- **Después**: `certResolver: "le"` configurado

### ✅ Recursos y Validación
- **Antes**: Sin límites de recursos
- **Después**: CPU y memoria configurados

## Uso

### Desarrollo Local
```bash
# Desplegar en minikube
helmfile -e minikube apply

# Verificar
kubectl get pods -n traefik
```

### Producción
```bash
# ArgoCD se encarga automáticamente del despliegue
# Verificar en ArgoCD UI
```

## Configuración de Dominios

### Para Producción
1. Editar `infra/envs/netcup/traefik-values.yaml`:
   ```yaml
   global:
     domain: "tu-dominio-real.com"
   ```

2. Editar `infra/envs/netcup/hello-values.yaml`:
   ```yaml
   ingress:
     hosts:
       - host: hello.tu-dominio-real.com
   ```

3. Actualizar email en ambos archivos:
   ```yaml
   additionalArguments:
     - "--certificatesresolvers.le.acme.email=albert@albertperez.dev
   ```

## Sync Waves

1. **Wave 0**: Traefik CRDs (bootstrap)
2. **Wave 1**: Traefik (apps/traefik)
3. **Wave 2**: Hello (apps/hello)

## Troubleshooting

### Problemas Comunes
1. **Certificados no se generan**: Verificar configuración de email y dominio
2. **Sync falla**: Verificar que los archivos de values existen
3. **DNS no resuelve**: Verificar configuración de dominio

### Logs Útiles
```bash
# Traefik logs
kubectl logs -n traefik -l app.kubernetes.io/name=traefik

# Hello logs
kubectl logs -n traefik -l app=hello
``` 
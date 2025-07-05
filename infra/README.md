# Infraestructura Kubernetes

Esta carpeta define todo lo necesario para desplegar el clúster mediante
**Argo CD**.

## Carpetas principales

- `bootstrap/` contiene los manifiestos para instalar Argo CD (`argocd.yaml`)
  y la aplicación raíz (`argocd-root.yaml`).
- `apps/` incluye las aplicaciones gestionadas por Argo CD. Aquí se encuentran
  los charts de Traefik y los CRDs, entre otros.
- `envs/` alberga los valores específicos de cada entorno (por ejemplo
  `minikube` para desarrollo local y `netcup` para producción).

## Bootstrap

> **Importante:** Primero debes aplicar los CRDs y el namespace antes del resto de recursos, o los manifiestos de ArgoCD y Kustomize fallarán.

```bash
kubectl apply -f infra/bootstrap/crds/
sleep 10  # Espera a que los CRDs estén disponibles
kubectl apply -k infra/bootstrap/
```

Después puedes acceder a la interfaz web de Argo CD o usar `argocd` CLI para
sincronizar y revisar el estado de las aplicaciones.

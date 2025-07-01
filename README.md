# Albert Cluster

Repositorio GitOps para gestionar mi clúster personal con **Argo CD**.
Toda la configuración de Kubernetes vive en este repositorio.

## Puesta en marcha rápida

Instala Argo CD y la aplicación raíz que sincronizará `infra/apps`:

```bash
kubectl apply -f infra/bootstrap/argocd.yaml
kubectl apply -f infra/bootstrap/argocd-root.yaml
```

Tras ello Argo CD aplicará automáticamente los charts y manifiestos
definidos en `infra/apps` (por ejemplo Traefik y sus CRDs).

## Estructura del repositorio

- `infra/bootstrap` contiene los manifiestos para instalar Argo CD y la
  aplicación raíz que apunta a `infra/apps`.
- `infra/apps` es la carpeta que Argo CD sincroniza; aquí se definen las
  aplicaciones y charts del clúster.
- `infra/envs` guarda valores específicos por entorno (p.ej. `minikube` y
  `netcup`).
- `docs` almacena la documentación de soporte.

## Acceso

Conecta al VPS con SSH:

```bash
ssh netcup
```

## hostname
albertperez 

La configuración de `kubectl` está en `kubeconfig ~/.kube/config`.


## Comandos básicos de Kubernetes

### local
```bash
kubectl config use-context minikube
```
### remote
```bash
kubectl config use-context netcup
```

```bash
kubectl config current-context  # Ver contexto actual
kubectl get nodes               # Ver nodos
kubectl get pods -A             # Todos los pods y namespaces
kubectl logs deploy/nginx       # Logs de un Deployment
kubectl apply -f archivo.yml    # Crear/actualizar recursos
kubectl delete -f archivo.yml
```

## Documentación

### local
- [Minikube local](docs/minikube-local.md)


# Albert Cluster

Notas para gestionar el clúster personal.

## Acceso

Conecta al VPS con SSH:

```bash
ssh root@188.68.42.77
```

## hostname
albertperez 

La configuración de `kubectl` está en `kubeconfig ~/.kube/config`.

## Comandos básicos de Kubernetes

```bash
kubectl get nodes            # Ver nodos
kubectl get pods -A          # Todos los pods y namespaces
kubectl logs deploy/nginx    # Logs de un Deployment
kubectl apply -f archivo.yml # Crear/actualizar recursos
kubectl delete -f archivo.yml
```

## Documentación

### local
- [Minikube local](docs/minikube-local.md)



Connect al VPS con SSH desde tu terminal:
```bash
ssh root@188.68.42.77
```


kuernetes config is in `kubeconfig ~/.kube/config`

comandos basicos de `kubectl`:
```bash
kubectl get nodes            # Ver nodos
kubectl get pods -A          # Todos los pods, todos los namespaces
kubectl logs deploy/nginx    # Logs del Deployment nginx
kubectl apply -f archivo.yml # Crear/actualizar recursos
kubectl delete -f archivo.yml
```
# Entorno “Stage” Local con Minikube

Este documento describe el flujo completo para levantar un mini-cluster de Kubernetes en tu Mac y desplegar tu aplicación **sin tocar tu clúster real**.

---

## 📦 Prerrequisitos

- **Docker Desktop** instalado y corriendo  
- **Homebrew**  
- **kubectl** (CLI de Kubernetes)  
- **minikube** (instalado con `brew install minikube`)  

---

## 🚀 Flujo de trabajo

### 1. Arrancar Minikube

Levantamos un clúster de un nodo usando Docker como driver (no necesitas hypervisor):

```bash
minikube start --driver=docker --cpus=4 --memory=8192
```
Ajusta --cpus y --memory según tengas disponibles en tu Mac.

### 2. “Apuntar” Docker a Minikube

Por defecto tus docker build crean imágenes en tu Docker local, pero Minikube no las ve.
Exporta variables de entorno para que tu CLI de Docker se conecte al demonio interno de Minikube:

```bash
eval $(minikube docker-env)
```

Sin esto, al hacer docker build tu imagen se queda en Docker Desktop y Kubernetes no la encuentra (tendrías que “push” a un registry externo).

### 3. Instalar Argo CD

Aplica los manifiestos de `infra/bootstrap` para desplegar Argo CD y la
aplicación raíz:

```bash
kubectl apply -f infra/bootstrap/argocd.yaml
kubectl apply -f infra/bootstrap/argocd-root.yaml
```

Esto instalará Traefik y sus CRDs, entre otras aplicaciones definidas en
`infra/apps`.

### 4. Construir y desplegar tu app

```bash
# 1. Construye la imagen DENTRO de Minikube
docker build -t mi-app:latest .

# 2. Aplica tus manifests (o Helm/Kustomize)
kubectl apply -f k8s/

# 3. (Si ya estaba desplegado) Actualiza el Deployment
kubectl set image deployment/mi-deployment mi-contenedor=mi-app:latest
```
  
4. Probar tus servicios

Ver pods y logs
```bash
kubectl get pods
kubectl logs -f <pod-name>
```

Ingress (opcional)
```bash
minikube addons enable ingress
echo "$(minikube ip)  mi-app.local" | sudo tee -a /etc/hosts
open http://mi-app.local
```

Dashboard de Kubernetes
```bash
minikube dashboard
```

### 5. Limpiar / parar el entorno
Cuando termines de probar:

```bash
# 1. Vuelve tu Docker host al valor por defecto
eval $(minikube docker-env --unset)

# 2. Para el clúster
minikube stop

# 3. (Opcional) Borra todo el estado de Minikube
minikube delete
```

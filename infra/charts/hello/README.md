# Hello Chart

Un chart de Helm simple para desplegar una aplicación "Hello World" usando http-echo.

## Características

- Deployment con http-echo
- Service para exponer la aplicación
- IngressRoute de Traefik para acceso externo
- Configuración flexible por entorno

## Instalación

### Usando Helmfile (Recomendado)

```bash
# Desde el directorio infra/apps
helmfile apply --environment minikube
```

### Usando Helm directamente

```bash
# Desde el directorio infra/charts/hello
helm install hello . --namespace traefik
```

## Configuración

### Valores por defecto

```yaml
replicaCount: 1
image:
  repository: hashicorp/http-echo
  tag: ""
  pullPolicy: IfNotPresent
service:
  type: ClusterIP
  port: 80
  targetPort: 5678
app:
  message: "¡Hola desde Minikube!"
```

### Personalización por entorno

- **Minikube**: `infra/envs/minikube/hello-values.yaml`
- **Netcup**: `infra/envs/netcup/hello-values.yaml`

## Acceso

Una vez desplegado, la aplicación estará disponible en:
- **Minikube**: `http://hello.127.0.0.1.nip.io`
- **Netcup**: `https://hello.yourdomain.com` (configurar dominio real)

## Migración desde instalación manual

Si tenías la aplicación instalada manualmente, puedes eliminarla con:

```bash
kubectl delete -f infra/charts/hello/hello-deployment.yaml
kubectl delete -f infra/charts/hello/hello-ingressroute.yaml
kubectl delete -f infra/charts/hello/hello-http-ingressroute.yaml
```

Y luego instalar con helmfile:

```bash
helmfile apply --environment minikube
``` 
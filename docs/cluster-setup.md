# Cluster Setup with Helm

This document outlines how to configure a Kubernetes cluster using Helm following best practices.

## 1. Install Kubernetes

Use a lightweight distribution such as **k3s** or a managed Kubernetes service. When installing k3s, disable the default Traefik ingress:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -
```

Verify cluster connectivity:

```bash
kubectl get nodes
```

## 2. Install Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Add required Helm repositories:

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add elastic https://helm.elastic.co
helm repo add supabase https://supabase.github.io/helm-chart
helm repo add firefly https://fireflyiii.github.io/kubernetes
helm repo update
```

## 3. Deploy Base Stack

### Traefik

```bash
helm install traefik traefik/traefik -n kube-system --create-namespace
```

### Prometheus and Grafana

```bash
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
```

### n8n

```bash
helm install n8n n8n/n8n -n automation --create-namespace
```

### Elasticsearch

```bash
helm install elasticsearch elastic/elasticsearch -n elastic --create-namespace
```

### Personal Website

Use a simple Helm chart or Kubernetes deployment with an ingress routed through Traefik.

### Supabase

```bash
helm install supabase supabase/supabase -n supabase --create-namespace
```

### Firefly III

```bash
helm install firefly firefly/fireflyiii -n finance --create-namespace
```

Each chart should be customized with a values file (`-f values.yaml`) containing persistent storage settings, resource limits and secrets.

## 4. Storage and Backups

Configure persistent volumes (e.g., Longhorn or another CSI driver) and set up regular backups for databases and critical data.

## 5. Security Best Practices

- Use namespaces to isolate applications.
- Enable role-based access control (RBAC).
- Store sensitive configuration in Kubernetes Secrets or an external secret store.


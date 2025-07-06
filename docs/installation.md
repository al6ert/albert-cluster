# Installation Guide

This guide will help you set up the Albert Cluster from scratch.

## Prerequisites

- Kubernetes cluster (minikube for local development, or a production cluster)
- `kubectl` configured to access your cluster
- `helm` (v3.x)
- `helmfile` (for managing multiple charts)

## Quick Start

### 1. Install Argo CD

Install Argo CD and the root application that will sync `infra/bootstrap`:

```bash
kubectl apply -f infra/bootstrap/argocd.yaml
kubectl apply -f infra/bootstrap/argocd-root.yaml
```

After this, Argo CD will automatically apply the charts and manifests defined in `infra/bootstrap` (e.g., Traefik and its CRDs).

### 2. Deploy Applications

Use Helmfile to manage the charts:

```bash
helmfile -f infra/apps/helmfile.yaml apply
```

### 3. Verify Argo CD Access

Ensure that the Argo CD web UI is reachable before continuing. If your cluster
exposes Traefik via a `LoadBalancer` service, check the external IP:

```bash
kubectl get svc -n kube-system traefik
```

Confirm that any DNS record for Argo CD points to this IP and that your
firewall allows access. If Argo CD is installed with its own `LoadBalancer`
service, verify it as well:

```bash
kubectl get svc -n argocd argocd-server
```

Initial login requires either a reachable `LoadBalancer` service or a working
Traefik ingress.

## Environment Setup

### Local Development (Minikube)

```bash
kubectl config use-context minikube
```

### Production (Netcup)

```bash
kubectl config use-context netcup
```

## Access

Connect to the VPS with SSH:

```bash
ssh netcup
```

## Hostname
`albertperez`

The `kubectl` configuration is in `~/.kube/config`.

## Basic Kubernetes Commands

### Check Current Context
```bash
kubectl config current-context  # View current context
```

### View Cluster Information
```bash
kubectl get nodes               # View nodes
kubectl get pods -A             # All pods and namespaces
```

### Application Management
```bash
kubectl logs deploy/nginx       # Deployment logs
kubectl apply -f archivo.yml    # Create/update resources
kubectl delete -f archivo.yml   # Delete resources
```

## Troubleshooting

If you encounter issues during installation:

1. Check that your `kubectl` context is correct
2. Verify that Argo CD pods are running: `kubectl get pods -n argocd`
3. Check Argo CD application status: `kubectl get applications -n argocd`
4. Review logs: `kubectl logs -n argocd deployment/argocd-server`

For more detailed troubleshooting, see the [Local Development Guide](minikube-local.md). 
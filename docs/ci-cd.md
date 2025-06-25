# CI/CD and Automated Updates

A GitOps workflow helps keep your cluster configuration in sync with this repository.

## 1. Repository Structure

- Store Helm charts or Helmfile definitions under `./charts` or `./helmfile`.
- Keep a `values` directory with custom configuration for each environment.

## 2. GitHub Actions Workflow

Create a workflow in `.github/workflows/deploy.yaml` to install or upgrade charts on every push to `main`:

```yaml
name: Deploy to Cluster
on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: azure/setup-helm@v3
      - name: Set up kubeconfig
        run: |
          mkdir -p ~/.kube
          echo "$KUBECONFIG_DATA" | base64 -d > ~/.kube/config
      - name: Helm upgrade
        run: |
          helm repo update
          helm upgrade --install traefik ./charts/traefik -n kube-system --create-namespace
          helm upgrade --install monitoring ./charts/monitoring -n monitoring --create-namespace
          # repeat for other charts
```

Store the base64-encoded kubeconfig in the repository secrets as `KUBECONFIG_DATA`.

## 3. Automated Chart Updates

Use [Renovate](https://github.com/renovatebot/renovate) or [Dependabot](https://github.com/dependabot) to automatically submit pull requests when upstream Helm chart versions change. Review and merge these PRs to trigger the workflow above.

## 4. Additional Recommendations

- Enable image scanning in the CI pipeline.
- Apply `helm diff` to preview changes before deployment.
- Use a staging environment before rolling out changes to production.


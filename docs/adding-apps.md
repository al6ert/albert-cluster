# Añadir una aplicación nueva

Patrón uniforme para toda app. El scaffold lo genera
[`scripts/new-app.sh`](scripts.md); el chart `hello` (`infra/charts/hello`) es
la referencia de "app bien hecha" (securityContext, HTTPRoute, NetworkPolicy,
resources).

## Cómo funciona el alta (modelo ApplicationSet)

Cada `infra/apps/<app>/app.yaml` es descubierto por el **ApplicationSet**
`cluster-apps` (git files generator): **crear la carpeta con su `app.yaml` y
pushear = la Application aparece en ArgoCD; borrarla = se poda**. No hay que
tocar ningún manifiesto de ArgoCD.

El helmfile raíz (`infra/apps/helmfile.yaml`) sigue existiendo para
`deploy-local.sh`, `bootstrap-prod.sh` y la validación de CI — la CI **falla**
si una app está en un registro y no en el otro.

## Decisión previa: ¿chart upstream o chart local?

- **Chart upstream** (Helm público): `--chart repo/chart --repo-url URL --version X`.
- **Chart local** (app propia): `--local` — copia `infra/charts/hello` como base.

## Pasos

### 1. Scaffold

```bash
# Upstream
./scripts/new-app.sh miapp --chart ejemplo/miapp \
  --repo-url https://charts.ejemplo.io --version 1.2.3

# App propia (chart local)
./scripts/new-app.sh miapp --local
```

Genera: `infra/apps/miapp/{app.yaml,helmfile.yaml.gotmpl,values.yaml}`,
`infra/envs/{minikube,netcup}/miapp-values.yaml`, la versión en
`versions.env` (con anotación `# renovate:`) y la línea en el helmfile raíz.

### 2. Values base y por entorno

- `infra/apps/miapp/values.yaml` — comunes a todos los entornos.
- `infra/envs/<entorno>/miapp-values.yaml` — lo que cambia por entorno
  (sobre todo el **hostname**).

### 3. Exponerla con Gateway API (no Ingress)

`HTTPRoute` al Gateway compartido; el TLS lo termina el Gateway:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: miapp
  namespace: miapp
spec:
  parentRefs:
    - name: traefik-gateway
      namespace: traefik
      sectionName: websecure
  hostnames:
    - miapp.albertperez.dev          # o miapp.127.0.0.1.nip.io en minikube
  rules:
    - backendRefs:
        - name: miapp
          port: 80
```

Si el chart upstream no soporta `HTTPRoute`, añádelo vía
`extraObjects`/`extraManifests` (ejemplo: grafana en el antiguo
prometheus-values) o como template del chart local.

### 4. Seguridad y límites (no opcional)

- **securityContext**: copia el del chart hello (`runAsNonRoot`,
  `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem`,
  `capabilities.drop: [ALL]`, `seccompProfile: RuntimeDefault`). El namespace
  nace con PSS `enforce: restricted` — un pod sin esto **se rechaza**. Si la
  app necesita más nivel, crea `infra/bootstrap/namespaces/<ns>.yaml` con el
  nivel justificado en comentario (patrón: monitoring/velero).
- **resources**: siempre requests/limits. Con la `ResourceQuota` del
  namespace, los pods sin límites solo entran si el `LimitRange` les pone
  defaults.
- **Políticas**: añade el bloque del namespace (NetworkPolicy default-deny +
  allows, ResourceQuota, LimitRange) en `infra/apps/policies/values.yaml`,
  copiando el bloque de `hello`.

### 5. CRDs (si el chart las trae)

Convención del repo: los charts NO instalan CRDs. Extráelas a
`infra/bootstrap/crds/` y regístralas en su kustomization:

```bash
source versions.env
helm template x repo/chart --version $VER --include-crds | \
  yq 'select(.kind == "CustomResourceDefinition")' > infra/bootstrap/crds/miapp-crds.yaml
```

y desactiva su instalación en values (`crds.install: false` o equivalente).

### 6. Validar y desplegar

```bash
# Render de la app suelta
source versions.env
helmfile --environment minikube -f infra/apps/miapp/helmfile.yaml.gotmpl template

# Local completo
./deploy-local.sh && ./tests/smoke.sh

# Push a dev → dev-ci valida → el ApplicationSet de minikube la despliega.
# Cuando esté verde: promociona dev → main (producción).
```

## Checklist

- [ ] `./scripts/new-app.sh` ejecutado (app.yaml + helmfile + values + versión + raíz)
- [ ] Hostname por entorno + `HTTPRoute` al Gateway `traefik-gateway`
- [ ] `securityContext` endurecido + `resources` (PSS restricted lo exige)
- [ ] Bloque en `infra/apps/policies/values.yaml` (netpol + quota + LimitRange)
- [ ] CRDs en `infra/bootstrap/crds/` si el chart las trae
- [ ] DNS: el wildcard `*.albertperez.dev` ya cubre subdominios nuevos
- [ ] `./tests/smoke.sh` en verde en local
- [ ] Si la app expone `/metrics`: annotation `k8s.grafana.io/scrape: "true"`
      (ver [observability.md](observability.md))

## Notas

- **PDB / réplicas**: en un cluster de un nodo, `replicaCount > 1` y
  `PodDisruptionBudget` no dan alta disponibilidad real — no los añadas por
  defecto ([architecture.md](architecture.md)).
- **Apps con estado**: antes del primer PV, revisa la estrategia de storage y
  añade el namespace al backup de Velero si procede
  ([runbook DR](runbooks/disaster-recovery.md)).

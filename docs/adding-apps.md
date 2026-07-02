# Añadir una aplicación nueva

Patrón uniforme para toda app. Usa el chart `hello` (`infra/charts/hello`) como
referencia de "app bien hecha".

## Decisión previa: ¿chart upstream o chart local?

- **Chart upstream** (Helm público): creas solo el `helmfile.yaml.gotmpl` que lo
  referencia + values. Ej.: cert-manager, traefik.
- **Chart local** (app propia sin chart público): creas un chart en
  `infra/charts/<app>/` y lo referencias con `chart: ../../charts/<app>`. Ej.:
  hello.

## Pasos

### 1. Release Helmfile

`infra/apps/<app>/helmfile.yaml.gotmpl`:

```yaml
repositories:
  - name: ejemplo
    url: https://charts.ejemplo.io

releases:
  - name: miapp
    namespace: miapp
    createNamespace: true
    chart: ejemplo/miapp
    version: {{ env "MIAPP_CHART_VERSION" }}
    values:
      - values.yaml
      - ../../envs/{{ .Environment.Name }}/miapp-values.yaml
    wait: true
    timeout: 300
```

### 2. Registrar en el Helmfile raíz

Añade la línea en `infra/apps/helmfile.yaml` **en la posición que define su
sync-wave** (el orden importa: depende de cert-manager/traefik):

```yaml
helmfiles:
  ...
  - path: ./miapp/helmfile.yaml.gotmpl        # wave 3
```

### 3. Values base y por entorno

- `infra/apps/<app>/values.yaml` — comunes a todos los entornos.
- `infra/envs/minikube/miapp-values.yaml` y `infra/envs/netcup/miapp-values.yaml`
  — lo único que cambia por entorno (sobre todo el **hostname**).

### 4. Exponerla con Gateway API (no Ingress)

Declara un `HTTPRoute` apuntando al Gateway compartido. El **TLS lo termina el
Gateway**, así que solo necesitas el hostname:

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

Si el chart upstream no soporta `HTTPRoute` nativo, añádelo vía
`extraObjects`/`extraManifests` del chart (ver el ejemplo de Grafana en
`infra/envs/netcup/prometheus-values.yaml`) o como manifiesto suelto en el chart
local.

### 5. Versión en `versions.env` (único sitio)

```bash
# renovate: datasource=helm depName=miapp registryUrl=https://charts.ejemplo.io
export MIAPP_CHART_VERSION="1.2.3"
```

El plugin de ArgoCD hace `source versions.env` del checkout, y los scripts/CI
también, así que **no hay que duplicar la versión en ningún otro fichero**. La
línea `# renovate:` es opcional pero recomendada: permite que Renovate proponga
actualizaciones (ver [updates.md](updates.md)).

### 6. DNS

En producción, `*.albertperez.dev` debería ser un wildcard apuntando al VPS, así
que `miapp.albertperez.dev` resuelve solo. Si usas registros A individuales, crea
el registro. En local, `nip.io` resuelve automáticamente.

### 7. Desplegar y validar

```bash
# Local
./deploy-local.sh
./tests/smoke.sh

# Producción: push a main → ArgoCD sincroniza
```

## Checklist

- [ ] `infra/apps/<app>/helmfile.yaml.gotmpl`
- [ ] Línea añadida en `infra/apps/helmfile.yaml` (sync-wave correcta)
- [ ] `values.yaml` base + `infra/envs/{minikube,netcup}/<app>-values.yaml`
- [ ] `HTTPRoute` al Gateway `traefik-gateway`
- [ ] Versión en `versions.env` (con anotación `# renovate:`)
- [ ] DNS (wildcard ya cubre, o registro nuevo)
- [ ] `securityContext` endurecido (runAsNonRoot, drop ALL caps, readOnlyRootFilesystem)
- [ ] `resources` (requests/limits) definidos
- [ ] `./tests/smoke.sh` en verde

## Buenas prácticas de seguridad por defecto

Copia el `securityContext` del chart `hello` (`infra/charts/hello/values.yaml`):
`runAsNonRoot`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem`,
`capabilities.drop: [ALL]`, `seccompProfile: RuntimeDefault`. Define siempre
`resources` para no dejar pods sin límites en un nodo compartido.

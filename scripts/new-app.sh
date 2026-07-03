#!/usr/bin/env bash
# Scaffold de una app nueva siguiendo el patrón del repo:
#   infra/apps/<name>/{app.yaml,helmfile.yaml.gotmpl,values.yaml}
#   infra/envs/{minikube,netcup}/<name>-values.yaml
#   versions.env (export <NAME>_CHART_VERSION con anotación renovate)
#   infra/apps/helmfile.yaml (línea en el helmfile raíz)
#
# Uso:
#   ./scripts/new-app.sh miapp --chart repo/miapp --repo-url https://charts.ejemplo.io --version 1.2.3
#   ./scripts/new-app.sh miapp --local          # chart propio en infra/charts/miapp
#   ...ambos aceptan: --namespace <ns> (default: <name>), --dry-run
#
# Tras el scaffold: commit + push a dev → el ApplicationSet crea la
# Application automáticamente (git files generator sobre app.yaml).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

NAME="${1:-}"; shift || true
CHART="" REPO_URL="" VERSION="" LOCAL=false NAMESPACE="" DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --chart)     CHART="$2"; shift 2 ;;
        --repo-url)  REPO_URL="$2"; shift 2 ;;
        --version)   VERSION="$2"; shift 2 ;;
        --local)     LOCAL=true; shift ;;
        --namespace) NAMESPACE="$2"; shift 2 ;;
        --dry-run)   DRY_RUN=true; shift ;;
        *) echo "❌ Opción desconocida: $1"; exit 1 ;;
    esac
done

if [[ -z "$NAME" ]] || [[ ! "$NAME" =~ ^[a-z0-9-]+$ ]]; then
    echo "Uso: $0 <name> (--chart repo/chart --repo-url URL --version X | --local) [--namespace ns] [--dry-run]"
    exit 1
fi
if ! $LOCAL && { [[ -z "$CHART" ]] || [[ -z "$REPO_URL" ]] || [[ -z "$VERSION" ]]; }; then
    echo "❌ Para chart upstream: --chart, --repo-url y --version son obligatorios (o usa --local)."
    exit 1
fi
if [[ -d "$ROOT/infra/apps/$NAME" ]]; then
    echo "❌ infra/apps/$NAME ya existe."
    exit 1
fi

NAMESPACE="${NAMESPACE:-$NAME}"
VAR="$(echo "$NAME" | tr 'a-z-' 'A-Z_')_CHART_VERSION"
REPO_NAME="${CHART%%/*}"

if $DRY_RUN; then
    echo "🔍 dry-run — se crearían:"
    echo "  infra/apps/$NAME/{app.yaml,helmfile.yaml.gotmpl,values.yaml}"
    echo "  infra/envs/{minikube,netcup}/$NAME-values.yaml"
    echo "  versions.env: export $VAR=\"${VERSION:-0.1.0}\""
    echo "  infra/apps/helmfile.yaml: - path: ./$NAME/helmfile.yaml.gotmpl"
    $LOCAL && echo "  (chart local: crea infra/charts/$NAME copiando infra/charts/hello)"
    exit 0
fi

mkdir -p "$ROOT/infra/apps/$NAME"

cat > "$ROOT/infra/apps/$NAME/app.yaml" << EOF
# Descubierto por el ApplicationSet (git files generator).
# Crear este fichero = la app aparece en ArgoCD; borrarlo = se poda.
name: $NAME
namespace: $NAMESPACE   # destination.namespace de la Application
wave: "3"       # documental: orden de bootstrap / helmfile raíz
EOF

if $LOCAL; then
    CHART_REF="../../charts/$NAME"
    REPOS_BLOCK=""
else
    CHART_REF="$CHART"
    REPOS_BLOCK="repositories:
  - name: $REPO_NAME
    url: $REPO_URL

"
fi

cat > "$ROOT/infra/apps/$NAME/helmfile.yaml.gotmpl" << EOF
environments:
  minikube: {}
  netcup: {}

---
${REPOS_BLOCK}releases:
  - name: $NAME
    namespace: $NAMESPACE
    createNamespace: true
    chart: $CHART_REF
    version: {{ env "$VAR" }}
    values:
      - values.yaml
      - ../../envs/{{ .Environment.Name }}/$NAME-values.yaml
    wait: true
    timeout: 300
EOF

cat > "$ROOT/infra/apps/$NAME/values.yaml" << EOF
# Values comunes a todos los entornos de $NAME.
# Overrides por entorno en infra/envs/{minikube,netcup}/$NAME-values.yaml.
EOF

for env in minikube netcup; do
    domain="127.0.0.1.nip.io"; [[ "$env" == "netcup" ]] && domain="albertperez.dev"
    cat > "$ROOT/infra/envs/$env/$NAME-values.yaml" << EOF
# infra/envs/$env/$NAME-values.yaml
# Hostname sugerido: $NAME.$domain (HTTPRoute → gateway traefik-gateway,
# listener websecure; el TLS lo termina el Gateway). Ver docs/adding-apps.md.
{}
EOF
done

# versions.env: insertar antes del bloque "Image versions"
if $LOCAL; then
    ANNOT="# Chart local (infra/charts/$NAME), se versiona a mano"
    VERSION="${VERSION:-0.1.0}"
else
    ANNOT="# renovate: datasource=helm depName=${CHART#*/} registryUrl=$REPO_URL"
fi
python3 - "$ROOT/versions.env" "$ANNOT" "$VAR" "$VERSION" << 'PYEOF'
import sys
path, annot, var, version = sys.argv[1:5]
s = open(path).read()
marker = "\n# Image versions"
block = f'{annot}\nexport {var}="{version}"\n'
s = s.replace(marker, f'\n{block}{marker}', 1)
open(path, 'w').write(s)
PYEOF

# helmfile raíz: añadir al final de la lista helmfiles
python3 - "$ROOT/infra/apps/helmfile.yaml" "$NAME" << 'PYEOF'
import sys
path, name = sys.argv[1:3]
lines = open(path).read().rstrip('\n').split('\n')
last = max(i for i, l in enumerate(lines) if l.strip().startswith('- path:'))
lines.insert(last + 1, f'  - path: ./{name}/helmfile.yaml.gotmpl         # wave 3')
open(path, 'w').write('\n'.join(lines) + '\n')
PYEOF

if $LOCAL && [[ ! -d "$ROOT/infra/charts/$NAME" ]]; then
    cp -R "$ROOT/infra/charts/hello" "$ROOT/infra/charts/$NAME"
    echo "📦 infra/charts/$NAME creado copiando el chart hello (renombra name/labels en Chart.yaml y _helpers.tpl)"
fi

echo "✅ App '$NAME' scaffolded."
echo ""
echo "📖 Checklist (ver docs/adding-apps.md):"
echo "  [ ] values: HTTPRoute al gateway traefik-gateway (hostname por entorno)"
echo "  [ ] securityContext endurecido (copiar del chart hello) + resources"
echo "  [ ] PSS del namespace: añade infra/bootstrap/namespaces/$NAMESPACE.yaml si necesita nivel ≠ restricted"
echo "  [ ] NetworkPolicy + ResourceQuota + LimitRange en infra/apps/policies/values.yaml"
echo "  [ ] Validar: source versions.env && helmfile --environment minikube -f infra/apps/$NAME/helmfile.yaml.gotmpl template"
echo "  [ ] ./deploy-local.sh && ./tests/smoke.sh"
echo "  [ ] Commit + push a dev → el ApplicationSet crea la Application sola"

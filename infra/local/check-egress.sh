#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_command kubectl
require_command python3
[[ -n "${OPENAI_API_KEY:-}" ]] || { printf 'OPENAI_API_KEY no está en el entorno del proceso\n' >&2; exit 2; }
export PATH="$ROOT/infra/.cache:$PATH"
kubectl -n poc-secrets get secret openai-api-key -o name >/dev/null
kubectl -n ate-system rollout status deployment/k8s-credential-provider --timeout=30s >/dev/null
kubectl ate get actor-template codex-poc -a ate-demo-counter -o yaml |
  python3 -c 'import os,sys; s=sys.stdin.read(); k=os.environ["OPENAI_API_KEY"]; assert k not in s and "substrate-placeholder" in s and "egress-trust-bundle" in s'
python3 - "$ROOT" <<'PY'
import os, sys
root = sys.argv[1]
secret = os.environ['OPENAI_API_KEY'].encode()
excluded = {'.git', '.cache', 'node_modules', 'dist', '.vite'}
for base, dirs, files in os.walk(root):
    dirs[:] = [d for d in dirs if d not in excluded]
    for name in files:
        path = os.path.join(base, name)
        try:
            if os.path.getsize(path) < 5_000_000 and secret in open(path, 'rb').read():
                raise SystemExit(f'La clave aparece en un archivo del proyecto: {path}')
        except (OSError, PermissionError):
            pass
PY
kubectl -n ate-system logs deployment/atenet-egress --all-containers=true --tail=500 |
  python3 -c 'import os,sys; assert os.environ["OPENAI_API_KEY"].encode() not in sys.stdin.buffer.read()'
kubectl -n ate-demo-counter logs deployment/codex-poc --tail=500 |
  python3 -c 'import os,sys; assert os.environ["OPENAI_API_KEY"].encode() not in sys.stdin.buffer.read()'
printf 'Egreso: clave ausente de plantilla, archivos y logs inspeccionados; proveedor listo\n'

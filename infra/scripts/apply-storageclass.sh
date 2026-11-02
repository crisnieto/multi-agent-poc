#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
project="${POC_PROJECT_NAME:-substrate-poc}"
[[ "$project" =~ ^[a-z][a-z0-9-]{2,30}$ ]] || { printf 'POC_PROJECT_NAME inválido\n' >&2; exit 2; }
command -v kubectl >/dev/null || { printf 'Falta kubectl\n' >&2; exit 2; }
sed "s/\${POC_PROJECT_NAME}/$project/g" "$root/infra/k8s/substrate/storageclass.yaml.tpl" | kubectl apply -f -

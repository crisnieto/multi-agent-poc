#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
"$ROOT/infra/local/down.sh"
if docker ps --format '{{.Names}}' | grep -Eq '^(kind-registry|substrate-control-plane|ate-)'; then
  printf 'Quedan contenedores locales de la prueba\n' >&2
  exit 1
fi
if command -v kind >/dev/null && kind get clusters | grep -Eq '^(substrate|ate)$'; then
  printf 'Queda el cluster kind\n' >&2
  exit 1
fi
printf 'Limpieza local verificada\n'

#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_command docker
if [[ -x "$UPSTREAM_DIR/hack/delete-kind-cluster.sh" ]]; then
  (cd "$UPSTREAM_DIR" && hack/delete-kind-cluster.sh)
else
  printf 'No se encontró el script de limpieza upstream. Revisar kind/registro manualmente.\n' >&2
  exit 2
fi

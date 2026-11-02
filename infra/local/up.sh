#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_command docker
require_command go
require_command kubectl
docker info >/dev/null 2>&1 || { printf 'Docker daemon no está activo\n' >&2; exit 2; }
memory="$(docker info --format '{{.MemTotal}}')"
(( memory >= 8 * 1024 * 1024 * 1024 )) || { printf 'Docker necesita al menos 8 GiB para esta prueba; detectado %s bytes\n' "$memory" >&2; exit 2; }
require_upstream
(cd "$UPSTREAM_DIR" && hack/create-kind-cluster.sh)
printf 'Cluster local creado con Substrate %s\n' "$SUBSTRATE_COMMIT"

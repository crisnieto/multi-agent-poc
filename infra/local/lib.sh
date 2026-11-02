#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UPSTREAM_DIR="$ROOT/infra/.cache/substrate"
SUBSTRATE_COMMIT="$(sed -n 's/^commit=//p' "$ROOT/infra/substrate.lock")"
SUBSTRATE_REPO="$(sed -n 's/^repository=//p' "$ROOT/infra/substrate.lock")"

require_command() {
  command -v "$1" >/dev/null || { printf 'Falta %s en PATH\n' "$1" >&2; exit 2; }
}

require_upstream() {
  require_command git
  if [[ ! -d "$UPSTREAM_DIR/.git" ]]; then
    mkdir -p "$UPSTREAM_DIR"
    git -C "$UPSTREAM_DIR" init -q
    git -C "$UPSTREAM_DIR" remote add origin "$SUBSTRATE_REPO"
  fi
  if ! git -C "$UPSTREAM_DIR" cat-file -e "$SUBSTRATE_COMMIT^{commit}" 2>/dev/null; then
    git -C "$UPSTREAM_DIR" fetch --depth 1 origin "$SUBSTRATE_COMMIT"
  fi
  git -C "$UPSTREAM_DIR" checkout -q --detach "$SUBSTRATE_COMMIT"
  [[ "$(git -C "$UPSTREAM_DIR" rev-parse HEAD)" == "$SUBSTRATE_COMMIT" ]] || {
    printf 'El checkout upstream no coincide con substrate.lock\n' >&2; exit 1;
  }
}

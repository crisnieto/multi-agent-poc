#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
runtime="$ROOT/infra/.runtime/local-demo"
if [[ "$(uname -s)" == Darwin ]] && command -v launchctl >/dev/null; then
  for label in dev.substrate-poc.local-web dev.substrate-poc.local-api; do
    launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
  done
fi
for name in web api; do
  pid_file="$runtime/$name.pid"
  if [[ -f "$pid_file" ]]; then
    pid="$(cat "$pid_file")"
    kill "$pid" 2>/dev/null || true
    rm -f "$pid_file"
  fi
done
"$ROOT/infra/local/clear-egress.sh"
printf 'Frontend y API detenidos; clúster local conservado para reinicio rápido\n'

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
report="$ROOT/infra/reports/local-components.md"
mkdir -p "$(dirname "$report")"
{
  printf '# Verificación local individual\n\nFecha: %s\nCommit Substrate: %s\n\n' "$(date -u +%FT%TZ)" "$(sed -n 's/^commit=//p' "$ROOT/infra/substrate.lock")"
  printf '| Componente | Comando | Resultado |\n|---|---|---|\n'
} > "$report"
run() {
  local name="$1" path="$2"
  if "$ROOT/$path"; then
    printf '| %s | `%s` | PASS |\n' "$name" "$path" >> "$report"
  else
    printf '| %s | `%s` | FAIL |\n' "$name" "$path" >> "$report"
    return 1
  fi
}
failures=0
run frontend infra/local/smoke-web.sh || failures=$((failures + 1))
run control-plane infra/local/smoke-control-plane.sh || failures=$((failures + 1))
run codex-actor infra/local/smoke-codex-actor.sh || failures=$((failures + 1))
run substrate infra/local/smoke-substrate.sh || failures=$((failures + 1))
if (( failures > 0 )); then
  printf '\nGate local individual: FAIL (%s componentes).\n' "$failures" >> "$report"
  exit 1
fi
printf '\nGate local individual: PASS.\n' >> "$report"

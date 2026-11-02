#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_command curl
require_command node
[[ -x "$ROOT/infra/.cache/kubectl-ate" ]] || { printf 'Ejecutar install-substrate.sh primero\n' >&2; exit 2; }
tmp="$(mktemp -d)"
port="${POC_SMOKE_PORT:-18081}"
pid=''
session_id=''
cleanup() {
  if [[ -n "$session_id" ]]; then
    curl -fsS -X DELETE -b "$tmp/cookies" "http://127.0.0.1:$port/api/sessions/$session_id" >/dev/null 2>&1 || true
  fi
  [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT
(
  cd "$ROOT/apps/control-plane"
  POC_DB_PATH="$tmp/poc.sqlite" POC_PORT="$port" POC_OPERATOR_PASSWORD=local-smoke-only \
    POC_SUBSTRATE_MODE=real POC_ATE_CLI="$ROOT/infra/.cache/kubectl-ate" node dist/server.js
) >"$tmp/server.log" 2>&1 &
pid=$!
for _ in {1..30}; do
  if curl -fsS "http://127.0.0.1:$port/api/healthz" >"$tmp/health.json" 2>/dev/null; then break; fi
  sleep 1
done
grep -q '"mode":"substrate"' "$tmp/health.json"
curl -fsS -X POST -H 'content-type: application/json' -d '{"password":"local-smoke-only"}' \
  -c "$tmp/cookies" "http://127.0.0.1:$port/api/auth/login" >/dev/null
curl -fsS -X POST -b "$tmp/cookies" "http://127.0.0.1:$port/api/sessions" >"$tmp/session.json"
session_id="$(node -e 'const s=JSON.parse(require("fs").readFileSync(process.argv[1]));if(s.source!=="substrate"||!s.actor_id.startsWith("poc-"))process.exit(1);console.log(s.id)' "$tmp/session.json")"
curl -fsS -b "$tmp/cookies" "http://127.0.0.1:$port/api/sessions/$session_id" >"$tmp/read.json"
node -e 'const s=JSON.parse(require("fs").readFileSync(process.argv[1]));if(s.id!==process.argv[2]||s.source!=="substrate")process.exit(1)' "$tmp/read.json" "$session_id"
curl -fsS -X DELETE -b "$tmp/cookies" "http://127.0.0.1:$port/api/sessions/$session_id" >/dev/null
session_id=''
printf 'Smoke sesiones reales: crear, consultar y eliminar actor de Substrate correctos\n'

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
port="${POC_PORT:-8080}"
password="${POC_OPERATOR_PASSWORD:-}"
[[ -n "$password" ]] || { printf 'Definir POC_OPERATOR_PASSWORD en el proceso\n' >&2; exit 2; }
export POC_OPERATOR_PASSWORD="$password"
tmp="$(mktemp -d)"
trap 'kill "${server_pid:-}" 2>/dev/null || true; rm -rf "$tmp"' EXIT
(cd "$ROOT/apps/control-plane" && POC_DB_PATH="$tmp/poc.sqlite" POC_PORT="$port" POC_OPERATOR_PASSWORD="$password" node dist/server.js) >"$tmp/server.log" 2>&1 &
server_pid=$!
for _ in {1..30}; do
  if curl -fsS "http://127.0.0.1:$port/api/healthz" >"$tmp/health.json"; then break; fi
  sleep 1
done
grep -q '"mode":"mock"' "$tmp/health.json"
login_code="$(curl -s -o /dev/null -w '%{http_code}' -c "$tmp/cookie" -H 'content-type: application/json' -d "$(node -e 'console.log(JSON.stringify({password:process.env.POC_OPERATOR_PASSWORD}))')" "http://127.0.0.1:$port/api/auth/login")"
[[ "$login_code" == 204 ]]
curl -fsS -b "$tmp/cookie" -X POST "http://127.0.0.1:$port/api/sessions" >"$tmp/session.json"
session_id="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1])).id)' "$tmp/session.json")"
curl -fsS -b "$tmp/cookie" -H 'content-type: application/json' -d '{"text":"hola"}' "http://127.0.0.1:$port/api/sessions/$session_id/requests" >"$tmp/request.json"
request_id="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1])).id)' "$tmp/request.json")"
curl -fsS -b "$tmp/cookie" "http://127.0.0.1:$port/api/requests/$request_id/events" >"$tmp/events.txt"
grep -q 'event: completed' "$tmp/events.txt"
grep -q '"source":"mock"' "$tmp/events.txt"
printf 'Smoke API mock: login, sesión, turno y SSE correctos\n'

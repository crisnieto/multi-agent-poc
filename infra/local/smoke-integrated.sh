#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_command curl
require_command node
require_command kubectl
require_command sqlite3
[[ -x "$ROOT/infra/.cache/kubectl-ate" ]] || { printf 'Ejecutar install-substrate.sh primero\n' >&2; exit 2; }
export PATH="$ROOT/infra/.cache:$PATH"
tmp="$(mktemp -d)"
port="${POC_SMOKE_PORT:-18082}"
pid=''
web_pid=''
session_id=''
cleanup() {
  if [[ -n "$session_id" ]]; then
    curl -fsS -X DELETE -b "$tmp/cookies" "http://127.0.0.1:$port/api/sessions/$session_id" >/dev/null 2>&1 || true
  fi
  [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true
  [[ -z "$web_pid" ]] || kill "$web_pid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT
kubectl -n poc-secrets get secret openai-api-key >/dev/null
(
  cd "$ROOT/apps/control-plane"
  env -u OPENAI_API_KEY POC_DB_PATH="$tmp/poc.sqlite" POC_PORT="$port" POC_OPERATOR_PASSWORD=local-smoke-only \
    POC_SUBSTRATE_MODE=real POC_ATE_CLI="$ROOT/infra/.cache/kubectl-ate" \
    POC_EGRESS_POLICY_PATH="$ROOT/infra/local/egress-policy.yaml" node dist/server.js
) >"$tmp/server.log" 2>&1 &
pid=$!
(
  cd "$ROOT/apps/web"
  POC_API_TARGET="http://127.0.0.1:$port" exec "$ROOT/apps/web/node_modules/.bin/vite" --host 127.0.0.1 --port 5174 --strictPort
) >"$tmp/web.log" 2>&1 &
web_pid=$!
for _ in {1..30}; do
  if curl -fsS "http://127.0.0.1:$port/api/healthz" >"$tmp/health.json" 2>/dev/null; then break; fi
  sleep 1
done
grep -q '"mode":"substrate"' "$tmp/health.json"
for _ in {1..30}; do
  if curl -fsS 'http://127.0.0.1:5174/?mode=real' >"$tmp/page.html" 2>/dev/null; then break; fi
  sleep 1
done
grep -q '/src/main.tsx' "$tmp/page.html"
curl -fsS 'http://127.0.0.1:5174/src/pages/Dashboard.tsx' >"$tmp/dashboard.js"
grep -q 'Nuevo chat' "$tmp/dashboard.js"
curl -fsS 'http://127.0.0.1:5174/api/healthz' >"$tmp/proxy-health.json"
grep -q '"mode":"substrate"' "$tmp/proxy-health.json"
curl -fsS -X POST -H 'content-type: application/json' -d '{"password":"local-smoke-only"}' \
  -c "$tmp/cookies" "http://127.0.0.1:$port/api/auth/login" >/dev/null
curl -fsS -X POST -b "$tmp/cookies" "http://127.0.0.1:$port/api/sessions" >"$tmp/session.json"
session_id="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1])).id)' "$tmp/session.json")"
actor_id="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1])).actor_id)' "$tmp/session.json")"
curl -fsS -X POST -b "$tmp/cookies" -H 'content-type: application/json' \
  -d '{"text":"Responde exactamente: listo"}' "http://127.0.0.1:$port/api/sessions/$session_id/requests" >"$tmp/request.json"
request_id="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1])).id)' "$tmp/request.json")"
curl -fsSN --max-time 150 -b "$tmp/cookies" "http://127.0.0.1:$port/api/requests/$request_id/events" >"$tmp/events.sse"
curl -fsS -b "$tmp/cookies" "http://127.0.0.1:$port/api/requests/$request_id" >"$tmp/result.json"
status="$(node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1]));console.log(r.status)' "$tmp/result.json")"
if [[ "$status" != completed ]]; then
  code="$(node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1]));console.log(r.error_code??"unknown")' "$tmp/result.json")"
  printf 'Turno integrado falló: %s\n' "$code" >&2
  exit 1
fi
grep -q '^event: delta$' "$tmp/events.sse"
grep -q '^event: completed$' "$tmp/events.sse"
for _ in {1..20}; do
  observed="$(sqlite3 "$tmp/poc.sqlite" "SELECT count(*) FROM events WHERE request_id = '$request_id' AND type = 'actor.observed' AND source = 'substrate' AND worker_id IS NOT NULL;")"
  [[ "$observed" == 1 ]] && break
  sleep 1
done
[[ "$observed" == 1 ]] || { printf 'No se persistió la asignación observada por Substrate\n' >&2; exit 1; }
kubectl ate get actor "$actor_id" -a ate-demo-counter -o json >"$tmp/actor.json"
node -e 'const a=JSON.parse(require("fs").readFileSync(process.argv[1]));if(a.status?.state!=="ACTOR_STATE_RUNNING")process.exit(1)' "$tmp/actor.json"
kubectl ate suspend actor "$actor_id" -a ate-demo-counter --mode=sync >/dev/null
kubectl ate get actor "$actor_id" -a ate-demo-counter -o json >"$tmp/suspended.json"
node -e 'const a=JSON.parse(require("fs").readFileSync(process.argv[1]));if(a.status?.state!=="ACTOR_STATE_SUSPENDED")process.exit(1)' "$tmp/suspended.json"
kubectl ate resume actor "$actor_id" -a ate-demo-counter >/dev/null
for _ in {1..30}; do
  kubectl ate get actor "$actor_id" -a ate-demo-counter -o json >"$tmp/resumed.json"
  if node -e 'const a=JSON.parse(require("fs").readFileSync(process.argv[1]));process.exit(a.status?.state==="ACTOR_STATE_RUNNING"?0:1)' "$tmp/resumed.json"; then break; fi
  sleep 1
done
node -e 'const a=JSON.parse(require("fs").readFileSync(process.argv[1]));if(a.status?.state!=="ACTOR_STATE_RUNNING"||!a.status?.workerAssignment?.worker?.name)process.exit(1)' "$tmp/resumed.json"
kubectl ate suspend actor "$actor_id" -a ate-demo-counter --mode=sync >/dev/null
printf 'Smoke integrado: frontend, turno Codex, SSE, asignación, suspensión y reanudación reales correctos\n'

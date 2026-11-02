#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_command curl
require_command node
export PATH="$ROOT/infra/.cache:$PATH"
tmp="$(mktemp -d)"
port=18083
actor_port=18094
pid=''
proxy_pid=''
session_id=''
cleanup() {
  [[ -z "$proxy_pid" ]] || kill "$proxy_pid" 2>/dev/null || true
  if [[ -n "$session_id" ]]; then curl -fsS -X DELETE -b "$tmp/cookies" "http://127.0.0.1:$port/api/sessions/$session_id" >/dev/null 2>&1 || true; fi
  [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT
(
  cd "$ROOT/apps/control-plane"
  env -u OPENAI_API_KEY POC_DB_PATH="$tmp/poc.sqlite" POC_PORT="$port" POC_OPERATOR_PASSWORD=local-smoke-only \
    POC_SUBSTRATE_MODE=real POC_IDLE_SECONDS=1 POC_ATE_CLI="$ROOT/infra/.cache/kubectl-ate" node dist/server.js
) >"$tmp/server.log" 2>&1 &
pid=$!
for _ in {1..30}; do if curl -fsS "http://127.0.0.1:$port/api/healthz" >/dev/null 2>&1; then break; fi; sleep 1; done
curl -fsS -X POST -H 'content-type: application/json' -d '{"password":"local-smoke-only"}' -c "$tmp/cookies" "http://127.0.0.1:$port/api/auth/login" >/dev/null
curl -fsS -X POST -b "$tmp/cookies" "http://127.0.0.1:$port/api/sessions" >"$tmp/session.json"
session_id="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1])).id)' "$tmp/session.json")"
actor_id="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1])).actor_id)' "$tmp/session.json")"
kubectl ate proxy actor "$actor_id" "$actor_port:8090" -a ate-demo-counter >"$tmp/proxy.log" 2>&1 &
proxy_pid=$!
for _ in {1..30}; do if curl -fsS --max-time 2 "http://127.0.0.1:$actor_port/healthz" >/dev/null 2>&1; then break; fi; sleep 1; done
curl -fsS -b "$tmp/cookies" "http://127.0.0.1:$port/api/topology" >"$tmp/busy.json"
node -e 'const t=JSON.parse(require("fs").readFileSync(process.argv[1]));const a=t.actors.find(x=>x.session_id===process.argv[2]);if(!a||a.state!=="running"||!a.worker_id||t.workers.length!==2||!t.workers.some(w=>w.worker_id===a.worker_id&&w.state==="busy"))process.exit(1)' "$tmp/busy.json" "$session_id"
kill "$proxy_pid" 2>/dev/null || true
proxy_pid=''
for _ in {1..20}; do
  curl -fsS -b "$tmp/cookies" "http://127.0.0.1:$port/api/topology" >"$tmp/idle.json"
  if node -e 'const t=JSON.parse(require("fs").readFileSync(process.argv[1]));const a=t.actors.find(x=>x.session_id===process.argv[2]);process.exit(a?.state==="suspended"?0:1)' "$tmp/idle.json" "$session_id"; then break; fi
  sleep 1
done
node -e 'const t=JSON.parse(require("fs").readFileSync(process.argv[1]));const a=t.actors.find(x=>x.session_id===process.argv[2]);if(!a||a.state!=="suspended"||t.workers.length!==2||!t.workers.every(w=>w.state==="idle"))process.exit(1)' "$tmp/idle.json" "$session_id"
printf 'Smoke topología real: actor asignado, worker ocupado, suspensión por inactividad y workers libres correctos\n'

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
[[ -n "${OPENAI_API_KEY:-}" ]] || { printf 'OPENAI_API_KEY debe existir solo como variable de proceso para el turno real\n' >&2; exit 2; }
tmp="$(mktemp -d)"
cleanup() {
  if [[ -n "${actor_pid:-}" ]]; then
    kill "$actor_pid" 2>/dev/null || true
    wait "$actor_pid" 2>/dev/null || true
  fi
  for _ in 1 2 3; do
    if rm -rf "$tmp" 2>/dev/null; then break; fi
    sleep 1
  done
}
trap cleanup EXIT
(cd "$ROOT/apps/codex-actor" && CODEX_MODEL=gpt-6-luna CODEX_HOME="$tmp/codex-home" CODEX_THREAD_STATE_PATH="$tmp/thread.json" ACTOR_PORT=8090 node dist/server.js) >"$tmp/server.log" 2>&1 &
actor_pid=$!
for _ in {1..30}; do
  if curl -fsS http://127.0.0.1:8090/healthz >"$tmp/health.json" 2>/dev/null; then break; fi
  sleep 1
done
grep -q '"status":"ok"' "$tmp/health.json"
request_id="$(node -e 'console.log(require("crypto").randomUUID())')"
curl -fsS -N --max-time 120 -H 'content-type: application/json' \
  -d "{\"request_id\":\"$request_id\",\"text\":\"Responde exactamente: listo\"}" \
  http://127.0.0.1:8090/turns >"$tmp/turn.sse"
if ! grep -q 'event: completed' "$tmp/turn.sse"; then
  printf 'El turno no completó. Eventos observados:\n' >&2
  grep '^event:' "$tmp/turn.sse" >&2 || true
  grep -o '"code":"[a-z_0-9]*"' "$tmp/turn.sse" >&2 || true
  if [[ "${POC_DEBUG_SAFE:-}" == true ]]; then
    grep '^codex_rpc_error ' "$tmp/server.log" >&2 || true
  fi
  exit 1
fi
grep -q 'event: delta' "$tmp/turn.sse"
curl -fsS -N --max-time 10 -H 'content-type: application/json' \
  -d "{\"request_id\":\"$request_id\",\"text\":\"Responde exactamente: listo\"}" \
  http://127.0.0.1:8090/turns >"$tmp/replay.sse"
cmp -s "$tmp/turn.sse" "$tmp/replay.sse"
printf 'Smoke Codex actor: healthz, turno real y evento terminal correctos\n'

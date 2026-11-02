#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_command kubectl
[[ -x "$ROOT/infra/.cache/kubectl-ate" ]] || { printf 'Ejecutar install-substrate.sh primero\n' >&2; exit 2; }
export PATH="$ROOT/infra/.cache:$PATH"
actor="poc-smoke-$(date +%s)"
proxy_pid=''
cleanup() {
  [[ -z "$proxy_pid" ]] || kill "$proxy_pid" 2>/dev/null || true
  kubectl ate delete actor "$actor" -a ate-demo-counter >/dev/null 2>&1 || true
}
trap cleanup EXIT
kubectl ate create actor "$actor" -a ate-demo-counter --template counter
kubectl ate proxy actor "$actor" -a ate-demo-counter >"$ROOT/infra/.cache/proxy.log" 2>&1 &
proxy_pid=$!
for _ in {1..60}; do
  if curl -fsS -X POST http://localhost:8000/ >"$ROOT/infra/.cache/counter-first.txt" 2>/dev/null; then break; fi
  sleep 2
done
grep -q 'preserved memory count: 1 | preserved file counter: 1' "$ROOT/infra/.cache/counter-first.txt"
kubectl ate get actor "$actor" -a ate-demo-counter
kubectl ate suspend actor "$actor" -a ate-demo-counter --mode=sync
kubectl ate get actor "$actor" -a ate-demo-counter
curl -fsS --max-time 120 -X POST http://localhost:8000/ >"$ROOT/infra/.cache/counter-second.txt"
grep -q 'preserved memory count: 2 | preserved file counter: 2' "$ROOT/infra/.cache/counter-second.txt"
kubectl ate get actor "$actor" -a ate-demo-counter
printf 'Smoke Substrate: actor %s creado, atendido, suspendido y reanudado\n' "$actor"

#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
[[ -n "${POC_AWS_REGION:-}" && -n "${POC_OPERATOR_PASSWORD:-}" ]] || {
  printf 'Configurar POC_AWS_REGION y POC_OPERATOR_PASSWORD\n' >&2; exit 2;
}
for binary in aws terraform kubectl curl node; do command -v "$binary" >/dev/null || exit 2; done
cluster="$(terraform -chdir="$root/infra/terraform" output -raw cluster_name)"
tmp="$(mktemp -d)"
port="${POC_SMOKE_PORT:-18084}"
session_id=''
pid=''
cleanup() {
  [[ -z "$session_id" ]] || curl -fsS -X DELETE -b "$tmp/cookies" "http://127.0.0.1:$port/api/sessions/$session_id" >/dev/null 2>&1 || true
  [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT
aws eks update-kubeconfig --name "$cluster" --region "$POC_AWS_REGION" --kubeconfig "$tmp/kubeconfig" >/dev/null
KUBECONFIG="$tmp/kubeconfig" kubectl -n ate-system port-forward svc/poc-web "$port:8080" >"$tmp/portforward.log" 2>&1 &
pid=$!
for _ in {1..30}; do
  if curl -fsS "http://127.0.0.1:$port/api/healthz" >"$tmp/health.json" 2>/dev/null; then break; fi
  sleep 1
done
grep -q '"mode":"substrate"' "$tmp/health.json"
node -e 'console.log(JSON.stringify({password:process.env.POC_OPERATOR_PASSWORD}))' |
  curl -fsS -X POST -H 'content-type: application/json' --data-binary @- -c "$tmp/cookies" "http://127.0.0.1:$port/api/auth/login" >/dev/null
curl -fsS -X POST -b "$tmp/cookies" "http://127.0.0.1:$port/api/sessions" >"$tmp/session.json"
session_id="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1])).id)' "$tmp/session.json")"
printf '{"text":"Responde exactamente: listo"}' |
  curl -fsS -X POST -b "$tmp/cookies" -H 'content-type: application/json' --data-binary @- \
    "http://127.0.0.1:$port/api/sessions/$session_id/requests" >"$tmp/request.json"
request_id="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1])).id)' "$tmp/request.json")"
curl -fsSN --max-time 180 -b "$tmp/cookies" "http://127.0.0.1:$port/api/requests/$request_id/events" >"$tmp/events.sse"
grep -q '^event: delta$' "$tmp/events.sse"
grep -q '^event: completed$' "$tmp/events.sse"
curl -fsS -b "$tmp/cookies" "http://127.0.0.1:$port/api/topology" >"$tmp/topology.json"
node -e 'const x=require(process.argv[1]);if(x.source!=="substrate"||x.workers.filter(w=>w.pod_name?.includes("codex-poc")).length!==2)process.exit(1)' "$tmp/topology.json"
printf 'PASS: sesión, turno Codex, SSE y dos workers observados en EKS\n'

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'kill "${web_pid:-}" 2>/dev/null || true; rm -rf "$tmp"' EXIT
(cd "$ROOT/apps/web" && ./node_modules/.bin/vite --host 127.0.0.1 --port 5173) >"$tmp/web.log" 2>&1 &
web_pid=$!
for _ in {1..30}; do
  if curl -fsS http://127.0.0.1:5173/ >"$tmp/index.html" 2>/dev/null; then break; fi
  sleep 1
done
if ! grep -q 'Agent Substrate PoC' "$tmp/index.html"; then cat "$tmp/web.log" >&2; exit 1; fi
curl -fsS http://127.0.0.1:5173/src/pages/LocalDemo.tsx >"$tmp/demo.js"
grep -q 'DATOS SIMULADOS' "$tmp/demo.js"
printf 'Smoke frontend standalone: Vite y demo simulada correctos\n'

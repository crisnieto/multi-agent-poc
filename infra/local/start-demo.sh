#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_command curl
require_command kubectl
require_command node
runtime="$ROOT/infra/.runtime/local-demo"
api_pid_file="$runtime/api.pid"
web_pid_file="$runtime/web.pid"
port="${POC_DEMO_API_PORT:-8080}"
web_port="${POC_DEMO_WEB_PORT:-5173}"
password="${POC_OPERATOR_PASSWORD:-local-poc-only}"
launchd_domain="gui/$(id -u)"
api_label='dev.substrate-poc.local-api'
web_label='dev.substrate-poc.local-web'
use_launchd=false
if [[ "$(uname -s)" == Darwin ]] && command -v launchctl >/dev/null; then use_launchd=true; fi

alive() { [[ -f "$1" ]] && kill -0 "$(cat "$1")" 2>/dev/null; }
service_active() { launchctl print "$launchd_domain/$1" >/dev/null 2>&1; }
if { [[ "$use_launchd" == true ]] && service_active "$api_label" && service_active "$web_label"; } ||
   { [[ "$use_launchd" == false ]] && alive "$api_pid_file" && alive "$web_pid_file"; }; then
  printf 'Demo ya activa: http://127.0.0.1:%s/?mode=real\n' "$web_port"
  exit 0
fi
if alive "$api_pid_file" || alive "$web_pid_file" ||
   { [[ "$use_launchd" == true ]] && { service_active "$api_label" || service_active "$web_label"; }; }; then
  printf 'Hay un proceso parcial. Ejecutar infra/local/stop-demo.sh antes de reiniciar.\n' >&2
  exit 2
fi
[[ -n "${OPENAI_API_KEY:-}" ]] || { printf 'OPENAI_API_KEY no está en el entorno; cargarla en el shell antes de iniciar\n' >&2; exit 2; }
[[ -f "$ROOT/apps/control-plane/dist/server.js" && -x "$ROOT/apps/web/node_modules/.bin/vite" ]] || {
  printf 'Ejecutar pnpm install && pnpm build antes de iniciar\n' >&2; exit 2;
}
[[ -x "$ROOT/infra/.cache/kubectl-ate" ]] || { printf 'Instalar Substrate local primero\n' >&2; exit 2; }
kubectl get node kind-control-plane -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -qx True
[[ "$(kubectl -n ate-demo-counter get workerpool codex-poc -o jsonpath='{.status.readyReplicas}')" == 2 ]] || {
  printf 'El pool Codex no tiene dos workers listos\n' >&2; exit 2;
}
for listen_port in "$port" "$web_port"; do
  if curl -fsS --max-time 1 "http://127.0.0.1:$listen_port/" >/dev/null 2>&1 ||
     lsof -nP -iTCP:"$listen_port" -sTCP:LISTEN >/dev/null 2>&1; then
    printf 'Puerto %s ocupado; detener el otro servicio o elegir POC_DEMO_*_PORT\n' "$listen_port" >&2; exit 2
  fi
done

mkdir -p "$runtime"
"$ROOT/infra/local/prepare-egress.sh"
"$ROOT/infra/local/check-egress.sh"
unset OPENAI_API_KEY

if [[ "$use_launchd" == true ]]; then
  POC_DEMO_ROOT="$ROOT" POC_DEMO_RUNTIME="$runtime" POC_DEMO_API_PORT="$port" \
    POC_DEMO_WEB_PORT="$web_port" POC_DEMO_PASSWORD="$password" \
    python3 - <<'PY'
import os, plistlib, shutil
root = os.environ['POC_DEMO_ROOT']
runtime = os.environ['POC_DEMO_RUNTIME']
api_port = os.environ['POC_DEMO_API_PORT']
web_port = os.environ['POC_DEMO_WEB_PORT']
common = {'RunAtLoad': True, 'KeepAlive': True}
services = {
    'api': {
        'Label': 'dev.substrate-poc.local-api',
        'ProgramArguments': [shutil.which('node'), 'dist/server.js'],
        'WorkingDirectory': f'{root}/apps/control-plane',
        'EnvironmentVariables': {
            'PATH': f'{root}/infra/.cache:' + os.environ['PATH'],
            'HOME': os.environ['HOME'],
            'POC_DB_PATH': f'{runtime}/poc.sqlite', 'POC_PORT': api_port,
            'POC_OPERATOR_PASSWORD': os.environ['POC_DEMO_PASSWORD'],
            'POC_SUBSTRATE_MODE': 'real', 'POC_ATE_CLI': f'{root}/infra/.cache/kubectl-ate',
            'POC_EGRESS_POLICY_PATH': f'{root}/infra/local/egress-policy.yaml',
        },
    },
    'web': {
        'Label': 'dev.substrate-poc.local-web',
        'ProgramArguments': [f'{root}/apps/web/node_modules/.bin/vite', '--host', '127.0.0.1', '--port', web_port, '--strictPort'],
        'WorkingDirectory': f'{root}/apps/web',
        'EnvironmentVariables': {'PATH': os.environ['PATH'], 'POC_API_TARGET': f'http://127.0.0.1:{api_port}'},
    },
}
for name, service in services.items():
    service.update(common)
    service['StandardOutPath'] = f'{runtime}/{name}.log'
    service['StandardErrorPath'] = f'{runtime}/{name}.log'
    with open(f'{runtime}/{name}.plist', 'wb') as file:
        plistlib.dump(service, file)
PY
  launchctl bootstrap "$launchd_domain" "$runtime/api.plist"
else
  (
    cd "$ROOT/apps/control-plane"
    env -u OPENAI_API_KEY POC_DB_PATH="$runtime/poc.sqlite" POC_PORT="$port" \
      POC_OPERATOR_PASSWORD="$password" POC_SUBSTRATE_MODE=real \
      POC_ATE_CLI="$ROOT/infra/.cache/kubectl-ate" \
      POC_EGRESS_POLICY_PATH="$ROOT/infra/local/egress-policy.yaml" \
      nohup node dist/server.js >"$runtime/api.log" 2>&1 </dev/null &
    printf '%s\n' "$!" >"$api_pid_file"
  )
fi
for _ in {1..30}; do
  if curl -fsS --max-time 2 "http://127.0.0.1:$port/api/healthz" 2>/dev/null | grep -q '"mode":"substrate"'; then break; fi
  sleep 1
done
if ! curl -fsS --max-time 2 "http://127.0.0.1:$port/api/healthz" | grep -q '"mode":"substrate"'; then
  printf 'La API no inició; revisar %s\n' "$runtime/api.log" >&2
  "$ROOT/infra/local/stop-demo.sh"
  exit 1
fi
if [[ "$use_launchd" == true ]]; then
  launchctl bootstrap "$launchd_domain" "$runtime/web.plist"
else
  (
    cd "$ROOT/apps/web"
    env -u OPENAI_API_KEY POC_API_TARGET="http://127.0.0.1:$port" \
      nohup "$ROOT/apps/web/node_modules/.bin/vite" --host 127.0.0.1 --port "$web_port" --strictPort \
      >"$runtime/web.log" 2>&1 </dev/null &
    printf '%s\n' "$!" >"$web_pid_file"
  )
fi
for _ in {1..30}; do
  if curl -fsS --max-time 2 "http://127.0.0.1:$web_port/?mode=real" >/dev/null 2>&1; then break; fi
  sleep 1
done
if ! curl -fsS --max-time 2 "http://127.0.0.1:$web_port/api/healthz" | grep -q '"mode":"substrate"'; then
  printf 'El frontend no inició o no conecta con la API; revisar %s\n' "$runtime/web.log" >&2
  "$ROOT/infra/local/stop-demo.sh"
  exit 1
fi
printf 'Demo lista: http://127.0.0.1:%s/?mode=real\n' "$web_port"
printf 'Contraseña local: %s\n' "$password"

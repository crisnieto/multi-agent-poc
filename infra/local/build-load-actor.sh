#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_command docker
require_command kubectl
require_command curl
require_command node
[[ -x "$ROOT/infra/.cache/kubectl-ate" ]] || { printf 'Ejecutar install-substrate.sh primero\n' >&2; exit 2; }
export PATH="$ROOT/infra/.cache:$PATH"
registry="localhost:${KIND_REGISTRY_PORT:-5001}"
image="$registry/codex-poc:$(git -C "$ROOT" rev-parse --short HEAD)"
node_arch="$(kubectl get node -o jsonpath='{.items[0].status.nodeInfo.architecture}')"
case "$node_arch" in amd64|arm64) ;; *) printf 'Arquitectura de nodo no compatible: %s\n' "$node_arch" >&2; exit 2;; esac
docker buildx build --platform "linux/$node_arch" --provenance=false --push -t "$image" -f "$ROOT/apps/codex-actor/Dockerfile" "$ROOT"
digest="$(curl -fsSI -H 'Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' "http://$registry/v2/codex-poc/manifests/${image##*:}" | tr -d '\r' | sed -n 's/^[Dd]ocker-[Cc]ontent-[Dd]igest: //p')"
[[ "$digest" == sha256:* ]] || { printf 'No se pudo obtener digest del registro local\n' >&2; exit 1; }
resolved_image="$registry/codex-poc@$digest"
worker_image="$(kubectl -n ate-demo-counter get workerpool counter -o jsonpath='{.spec.workerImage}')"
[[ -n "$worker_image" ]] || { printf 'No se encontró imagen de worker instalada\n' >&2; exit 1; }
sed "s|__WORKER_IMAGE__|$worker_image|" "$ROOT/infra/local/actor-workerpool.yaml" | kubectl apply -f -
for _ in {1..30}; do
  if kubectl -n ate-demo-counter get deployment codex-poc >/dev/null 2>&1; then break; fi
  sleep 1
done
kubectl -n ate-demo-counter rollout status deployment/codex-poc --timeout=5m
if kubectl ate get actor-template codex-poc -a ate-demo-counter -o yaml >"$ROOT/infra/.cache/actor-template-current.yaml" 2>/dev/null; then
  if [[ "${POC_REPLACE_TEMPLATE:-false}" == true ]]; then
    active="$(kubectl ate get actors -a ate-demo-counter -o json | node -e 'let data="";process.stdin.on("data",x=>data+=x).on("end",()=>{let a=JSON.parse(data).actors??[];console.log(a.filter(x=>x.actorTemplate?.name==="codex-poc").length)})')"
    [[ "$active" == 0 ]] || { printf 'No se reemplaza plantilla con %s actores existentes\n' "$active" >&2; exit 1; }
    kubectl ate delete actor-template codex-poc -a ate-demo-counter >/dev/null
    sed "s|__ACTOR_IMAGE__|$resolved_image|" "$ROOT/infra/local/actor-template.yaml" | kubectl ate create actor-template -f -
  elif ! grep -Fq "$resolved_image" "$ROOT/infra/.cache/actor-template-current.yaml"; then
    printf 'Ya existe la plantilla codex-poc con otra imagen; eliminar los actores y la plantilla antes de cambiarla\n' >&2
    exit 1
  fi
else
  sed "s|__ACTOR_IMAGE__|$resolved_image|" "$ROOT/infra/local/actor-template.yaml" | kubectl ate create actor-template -f -
fi
printf 'Actor template codex-poc registrado con digest %s\n' "$digest"

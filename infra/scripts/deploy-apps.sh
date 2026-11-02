#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
region="${POC_AWS_REGION:-}"
[[ -n "$region" ]] || { printf 'Configurar POC_AWS_REGION\n' >&2; exit 2; }
[[ -n "${OPENAI_API_KEY:-}" && -n "${POC_OPERATOR_PASSWORD:-}" ]] || {
  printf 'Faltan OPENAI_API_KEY o POC_OPERATOR_PASSWORD en el entorno; nunca ponerlos en archivos versionados\n' >&2; exit 2;
}
for binary in aws terraform kubectl node; do command -v "$binary" >/dev/null || { printf 'Falta %s\n' "$binary" >&2; exit 2; }; done
[[ -x "$root/infra/.cache/kubectl-ate" && -f "$root/infra/.runtime/aws/images.json" ]] || {
  printf 'Faltan kubectl-ate local o digests de imágenes; ejecutar install-substrate.sh y build-push.sh\n' >&2; exit 2;
}
export PATH="$root/infra/.cache:$PATH"
cluster="$(terraform -chdir="$root/infra/terraform" output -raw cluster_name)"
kubeconfig="$(mktemp)"
trap 'rm -f "$kubeconfig"' EXIT
aws eks update-kubeconfig --name "$cluster" --region "$region" --kubeconfig "$kubeconfig" >/dev/null
export KUBECONFIG="$kubeconfig"
kubectl -n ate-system get deployment ate-api-server >/dev/null

kubectl create namespace ate-demo-counter --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create namespace poc-secrets --dry-run=client -o yaml | kubectl apply -f - >/dev/null
if ! kubectl ate get atespace ate-demo-counter >/dev/null 2>&1; then
  kubectl ate create atespace ate-demo-counter
fi

# Las credenciales pasan por stdin a Secrets. Ni la imagen, ni los manifiestos
# versionados, ni Terraform contienen sus valores.
printf '%s' "$OPENAI_API_KEY" |
  kubectl -n poc-secrets create secret generic openai-api-key --from-file=token=/dev/stdin --dry-run=client -o yaml |
  kubectl apply -f - >/dev/null
printf '%s' "$POC_OPERATOR_PASSWORD" |
  kubectl -n ate-system create secret generic poc-operator-login --from-file=password=/dev/stdin --dry-run=client -o yaml |
  kubectl apply -f - >/dev/null
cat <<'EOF' | kubectl apply -f - >/dev/null
apiVersion: v1
kind: ConfigMap
metadata:
  name: k8s-credential-provider-namespace-policy
  namespace: ate-system
data:
  namespace-policy.yaml: |
    policies:
    - atespace: ate-demo-counter
      allowedNamespaces:
      - poc-secrets
EOF
kubectl -n ate-system rollout restart deployment/k8s-credential-provider >/dev/null
kubectl -n ate-system rollout status deployment/k8s-credential-provider --timeout=5m >/dev/null

images="$root/infra/.runtime/aws/images.json"
get_image() { node -e 'const x=require(process.argv[1]);const v=x[process.argv[2]];if(!v||!/@sha256:[a-f0-9]{64}$/.test(v))process.exit(1);console.log(v)' "$images" "$1"; }
worker_image="$(get_image worker)"
actor_image="$(get_image actor)"
web_image="$(get_image web)"
control_image="$(get_image controlPlane)"

sed "s|__WORKER_IMAGE__|$worker_image|" "$root/infra/local/actor-workerpool.yaml" | kubectl apply -f -
kubectl -n ate-demo-counter rollout status deployment/codex-poc --timeout=10m
if kubectl ate get actor-template codex-poc -a ate-demo-counter -o yaml >"$root/infra/.runtime/aws/current-template.yaml" 2>/dev/null; then
  grep -Fq "$actor_image" "$root/infra/.runtime/aws/current-template.yaml" || {
    printf 'La plantilla existente usa otra imagen; revisar actores antes de reemplazarla\n' >&2; exit 1;
  }
else
  sed "s|__ACTOR_IMAGE__|$actor_image|" "$root/infra/local/actor-template.yaml" | kubectl ate create actor-template -f -
fi

public_access="$(terraform -chdir="$root/infra/terraform" output -raw public_access_enabled)"
[[ "$public_access" == true || "$public_access" == false ]] || { printf 'Salida public_access_enabled inválida\n' >&2; exit 1; }
POC_WEB_IMAGE="$web_image" POC_CONTROL_IMAGE="$control_image" POC_PUBLIC_ACCESS="$public_access" node - "$root/infra/k8s/apps/apps.yaml.tpl" <<'NODE' | kubectl apply -f -
const fs=require('fs');let s=fs.readFileSync(process.argv[2],'utf8');
const publicAccess=process.env.POC_PUBLIC_ACCESS==='true';
for(const [name,value] of [['__WEB_IMAGE__',process.env.POC_WEB_IMAGE],['__CONTROL_PLANE_IMAGE__',process.env.POC_CONTROL_IMAGE],
  ['__WEB_SERVICE_TYPE__',publicAccess?'NodePort':'ClusterIP'],
  ['__WEB_NODE_PORT_LINE__',publicAccess?'    nodePort: 30080':'']]){
  if(s.split(name).length!==2||value===undefined)process.exit(1);
  s=s.replace(name,value);
}
process.stdout.write(s);
NODE
kubectl -n ate-system rollout status deployment/poc-control-plane --timeout=10m
kubectl -n ate-system rollout status deployment/poc-web --timeout=5m
printf 'Aplicaciones privadas listas. Acceso: aws eks update-kubeconfig --name %s --region %s && kubectl -n ate-system port-forward svc/poc-web 8080:8080\n' "$cluster" "$region"
if [[ "$public_access" == true ]]; then
  printf 'Acceso público TLS: %s\n' "$(terraform -chdir="$root/infra/terraform" output -raw public_web_url)"
fi

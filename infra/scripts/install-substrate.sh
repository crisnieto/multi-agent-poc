#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
region="${POC_AWS_REGION:-}"
[[ -n "$region" ]] || { printf 'Configurar POC_AWS_REGION\n' >&2; exit 2; }
for binary in aws terraform kubectl go docker node; do
  command -v "$binary" >/dev/null || { printf 'Falta %s en PATH\n' "$binary" >&2; exit 2; }
done
tf_dir="$root/infra/terraform"
[[ -f "$tf_dir/terraform.tfstate" ]] || { printf 'Falta estado Terraform; no hay EKS que instalar\n' >&2; exit 2; }
state_region="$(terraform -chdir="$tf_dir" output -raw aws_region)"
[[ "$state_region" == "$region" ]] || { printf 'Región Terraform/POC_AWS_REGION distinta\n' >&2; exit 2; }
cluster="$(terraform -chdir="$tf_dir" output -raw cluster_name)"
bucket="$(terraform -chdir="$tf_dir" output -raw snapshot_bucket)"
web_repo="$(terraform -chdir="$tf_dir" output -json ecr_repositories | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const u=JSON.parse(s).web;if(!u)process.exit(1);console.log(u)})')"
registry="${web_repo%%/*}"
base_repo="${web_repo%/web}"
[[ "$registry" == *".dkr.ecr.$region.amazonaws.com" && -n "$bucket" ]] || {
  printf 'Salida ECR/S3 de Terraform inválida\n' >&2; exit 2;
}

"$root/infra/scripts/prepare-substrate-eks.sh"
kubeconfig="$(mktemp)"
trap 'rm -f "$kubeconfig"' EXIT
aws eks update-kubeconfig --name "$cluster" --region "$region" --kubeconfig "$kubeconfig" >/dev/null
export KUBECONFIG="$kubeconfig"
kubectl get nodes >/dev/null
"$root/infra/scripts/apply-storageclass.sh"
aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry" >/dev/null
export KO_DOCKER_REPO="$base_repo"
export KO_DEFAULTPLATFORMS=linux/amd64
export NO_DEV_ENV=1
unset ATE_INSTALL_KIND

worktree="$root/infra/.cache/substrate-eks"
(cd "$worktree" && go run ./cmd/ate-setup deploy ate-system \
  --no-dev-env \
  --sandbox-classes=gvisor \
  --snapshot-location="s3://$bucket/atespaces/" \
  --ateapi-postgres-storage-class=substrate-poc-gp3 \
  --credential-provider='{"name":"k8s.io"}' \
  --ingress-allowed-spiffe-ids='spiffe://cluster.local/ns/ate-system/sa/atenet-client,spiffe://cluster.local/ns/poc/sa/control-plane' \
  --rollout-timeout=10m)
kubectl -n ate-system rollout status deployment/ate-api-server --timeout=10m
kubectl -n ate-system get pods
printf 'Substrate instalado desde %s en %s\n' "$(sed -n 's/^commit=//p' "$root/infra/substrate.lock")" "$cluster"

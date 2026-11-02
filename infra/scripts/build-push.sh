#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
region="${POC_AWS_REGION:-}"
project="${POC_PROJECT_NAME:-substrate-poc}"
[[ -n "$region" && "$project" =~ ^[a-z][a-z0-9-]{2,30}$ ]] || { printf 'Configurar región/proyecto válidos\n' >&2; exit 2; }
for binary in aws terraform docker go git node; do command -v "$binary" >/dev/null || { printf 'Falta %s\n' "$binary" >&2; exit 2; }; done
[[ -f "$root/infra/terraform/terraform.tfstate" ]] || { printf 'Falta estado Terraform\n' >&2; exit 2; }
[[ "$(terraform -chdir="$root/infra/terraform" output -raw aws_region)" == "$region" ]] || { printf 'Región Terraform distinta\n' >&2; exit 2; }

repo_json="$(terraform -chdir="$root/infra/terraform" output -json ecr_repositories)"
repo() { printf '%s' "$repo_json" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const u=JSON.parse(s)[process.argv[1]];if(!u)process.exit(1);console.log(u)})' "$1"; }
web_repo="$(repo web)"
registry="${web_repo%%/*}"
base_repo="${web_repo%/web}"
[[ "$registry" == *".dkr.ecr.$region.amazonaws.com" ]] || { printf 'Registro ECR inválido\n' >&2; exit 2; }
aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry" >/dev/null

source_dir="$root/infra/.cache/substrate"
commit="$(sed -n 's/^commit=//p' "$root/infra/substrate.lock")"
[[ -d "$source_dir/.git" && "$(git -C "$source_dir" rev-parse HEAD)" == "$commit" ]] || { printf 'Falta checkout Substrate fijado\n' >&2; exit 2; }
mkdir -p "$root/apps/control-plane/assets" "$root/infra/.runtime/aws"
(cd "$source_dir" && env -u OPENAI_API_KEY CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o "$root/apps/control-plane/assets/kubectl-ate" ./cmd/kubectl-ate)

tag="$(git -C "$root" rev-parse --short=12 HEAD)-$(date -u +%Y%m%d%H%M%S)"
web_image=''
control_image=''
actor_image=''
for component in web control-plane codex-actor; do
  repository="$(repo "$component")"
  env -u OPENAI_API_KEY docker buildx build --platform linux/amd64 --provenance=false --push \
    -t "$repository:$tag" -f "$root/apps/$component/Dockerfile" "$root"
  digest="$(aws ecr describe-images --region "$region" --repository-name "$project/$component" \
    --image-ids "imageTag=$tag" --query 'imageDetails[0].imageDigest' --output text)"
  [[ "$digest" == sha256:* ]] || { printf 'Digest ECR faltante para %s\n' "$component" >&2; exit 1; }
  case "$component" in
    web) web_image="$repository@$digest" ;;
    control-plane) control_image="$repository@$digest" ;;
    codex-actor) actor_image="$repository@$digest" ;;
  esac
done

export KO_DOCKER_REPO="$base_repo" KO_DEFAULTPLATFORMS=linux/amd64
ko_binary="$(cd "$source_dir/hack/tools/ko" && go tool -n ko)"
worker_image="$(cd "$source_dir" && env -u OPENAI_API_KEY "$ko_binary" build --base-import-paths ./cmd/ateworker-gvisor | tail -n 1)"
[[ "$worker_image" == "$base_repo/ateworker-gvisor@sha256:"* ]] || { printf 'Digest de worker inválido\n' >&2; exit 1; }

POC_WEB_IMAGE="$web_image" POC_CONTROL_IMAGE="$control_image" \
  POC_ACTOR_IMAGE="$actor_image" POC_WORKER_IMAGE="$worker_image" \
  node - <<'NODE' > "$root/infra/.runtime/aws/images.json"
const data={web:process.env.POC_WEB_IMAGE,controlPlane:process.env.POC_CONTROL_IMAGE,
  actor:process.env.POC_ACTOR_IMAGE,worker:process.env.POC_WORKER_IMAGE};
if(Object.values(data).some(v=>!v?.includes('@sha256:')))process.exit(1);
console.log(JSON.stringify(data,null,2));
NODE
chmod 600 "$root/infra/.runtime/aws/images.json"
printf 'Imágenes publicadas por digest; referencias en infra/.runtime/aws/images.json (ignorado por Git)\n'

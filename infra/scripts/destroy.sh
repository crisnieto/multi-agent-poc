#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
vars="${POC_TFVARS:-}"
[[ -n "$vars" && -f "$vars" ]] || { printf 'Configurar POC_TFVARS con el archivo real de esta ventana\n' >&2; exit 2; }
[[ -n "${POC_AWS_REGION:-}" ]] || { printf 'Configurar POC_AWS_REGION\n' >&2; exit 2; }
for binary in aws terraform; do command -v "$binary" >/dev/null || { printf 'Falta %s\n' "$binary" >&2; exit 2; }; done
tf_dir="${POC_TERRAFORM_DIR:-$root/infra/terraform}"
[[ -f "$tf_dir/terraform.tfstate" ]] || { printf 'Falta estado Terraform local; no se puede destruir con seguridad\n' >&2; exit 2; }
state_region="$(terraform -chdir="$tf_dir" output -raw aws_region)" || { printf 'El estado no contiene la región\n' >&2; exit 2; }
[[ "$state_region" == "$POC_AWS_REGION" ]] || { printf 'Región del estado y POC_AWS_REGION difieren\n' >&2; exit 2; }
state_project="$(terraform -chdir="$tf_dir" output -raw cluster_name)" || { printf 'El estado no contiene el clúster\n' >&2; exit 2; }
[[ "$state_project" == "${POC_PROJECT_NAME:-substrate-poc}" ]] || { printf 'El proyecto del estado y POC_PROJECT_NAME difieren\n' >&2; exit 2; }
aws sts get-caller-identity --region "$POC_AWS_REGION" >/dev/null
if command -v kubectl >/dev/null; then
  if aws eks describe-cluster --name "$state_project" --region "$POC_AWS_REGION" >/dev/null 2>&1; then
    kubeconfig="$(mktemp)"
    trap 'rm -f "$kubeconfig"' EXIT
    aws eks update-kubeconfig --name "$state_project" --region "$POC_AWS_REGION" --kubeconfig "$kubeconfig" >/dev/null
    if ! KUBECONFIG="$kubeconfig" kubectl delete pvc --all -A --wait=true --timeout=180s; then
      printf 'No se borraron todos los PVC; Terraform continuará y la auditoría detectará EBS residuales\n' >&2
    fi
  fi
fi
terraform -chdir="$tf_dir" destroy -input=false -auto-approve -var-file="$vars"
"$root/infra/scripts/audit-residuals.sh"

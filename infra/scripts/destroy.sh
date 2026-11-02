#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
vars="${POC_TFVARS:-}"
[[ -n "$vars" && -f "$vars" ]] || { printf 'Configurar POC_TFVARS con el archivo real de esta ventana\n' >&2; exit 2; }
[[ -n "${POC_AWS_REGION:-}" ]] || { printf 'Configurar POC_AWS_REGION\n' >&2; exit 2; }
for binary in aws terraform node; do command -v "$binary" >/dev/null || { printf 'Falta %s\n' "$binary" >&2; exit 2; }; done
tf_dir="${POC_TERRAFORM_DIR:-$root/infra/terraform}"
[[ -f "$tf_dir/terraform.tfstate" ]] || { printf 'Falta estado Terraform local; no se puede destruir con seguridad\n' >&2; exit 2; }
project="${POC_PROJECT_NAME:-substrate-poc}"
state_count="$(terraform -chdir="$tf_dir" state list | wc -l | tr -d ' ')"
if (( state_count > 0 )); then
  # Terraform puede perder los outputs tras una destrucción parcial. Identificar
  # el estado por el clúster o la VPC y su ARN, no por outputs opcionales.
  identity="$(terraform -chdir="$tf_dir" show -json | node -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      const rs=JSON.parse(s).values?.root_module?.resources||[];
      const c=rs.find(r=>r.address==="aws_eks_cluster.poc");
      const v=rs.find(r=>r.address==="aws_vpc.poc");
      const name=c?.values?.name||v?.values?.tags_all?.Project;
      const arn=c?.values?.arn||v?.values?.arn;
      const region=arn?.split(":")[3];
      if(!name||!region)process.exit(1);
      console.log(`${name}\t${region}`)
    })')" || { printf 'No se pudo identificar el estado parcial de la PoC\n' >&2; exit 2; }
  IFS=$'\t' read -r state_project state_region <<<"$identity"
  [[ "$state_region" == "$POC_AWS_REGION" && "$state_project" == "$project" ]] || {
    printf 'Región o proyecto del estado no coincide con la ventana\n' >&2; exit 2;
  }
fi
aws sts get-caller-identity --region "$POC_AWS_REGION" >/dev/null
if (( state_count > 0 )) && command -v kubectl >/dev/null; then
  cluster_status="$(aws eks describe-cluster --name "$project" --region "$POC_AWS_REGION" --query cluster.status --output text 2>/dev/null || true)"
  if [[ "$cluster_status" == ACTIVE ]]; then
    kubeconfig="$(mktemp)"
    trap 'rm -f "$kubeconfig"' EXIT
    aws eks update-kubeconfig --name "$project" --region "$POC_AWS_REGION" --kubeconfig "$kubeconfig" >/dev/null
    if ! KUBECONFIG="$kubeconfig" kubectl delete pvc --all -A --wait=true --timeout=180s; then
      printf 'No se borraron todos los PVC; Terraform continuará y la auditoría detectará EBS residuales\n' >&2
    fi
  fi
fi
if (( state_count > 0 )); then terraform -chdir="$tf_dir" destroy -input=false -auto-approve -var-file="$vars"; fi

# El CSI puede dejar un volumen dinámico disponible tras eliminar el PVC.
# Solo se eliminan volúmenes desasociados y etiquetados para esta PoC.
volume_json="$(aws ec2 describe-volumes --region "$POC_AWS_REGION" --filters "Name=tag:Project,Values=$project" "Name=status,Values=available" --output json)"
volume_ids="$(printf '%s' "$volume_json" | node -e '
  let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
    for(const v of JSON.parse(s).Volumes||[]){
      if(!/^vol-[0-9a-f]+$/.test(v.VolumeId)||v.State!=="available"||v.Attachments?.length)process.exit(1);
      console.log(v.VolumeId)
    }
  })')"
for volume_id in $volume_ids; do
  aws ec2 delete-volume --region "$POC_AWS_REGION" --volume-id "$volume_id"
  aws ec2 wait volume-deleted --region "$POC_AWS_REGION" --volume-ids "$volume_id"
done
"$root/infra/scripts/audit-residuals.sh"

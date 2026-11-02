#!/usr/bin/env bash
set -euo pipefail
project="${POC_PROJECT_NAME:-substrate-poc}"
region="${POC_AWS_REGION:-}"
[[ "$project" =~ ^[a-z][a-z0-9-]{2,30}$ && -n "$region" ]] || {
  printf 'Configurar POC_PROJECT_NAME válido y POC_AWS_REGION\n' >&2; exit 2;
}
for binary in aws terraform; do command -v "$binary" >/dev/null || { printf 'Falta %s\n' "$binary" >&2; exit 2; }; done
root="$(cd "$(dirname "$0")/../.." && pwd)"
tf_dir="${POC_TERRAFORM_DIR:-$root/infra/terraform}"
[[ -f "$tf_dir/terraform.tfstate" ]] || { printf 'Falta estado Terraform local; auditoría insegura\n' >&2; exit 2; }
state_count="$(terraform -chdir="$tf_dir" state list | wc -l | tr -d ' ')"
aws sts get-caller-identity --region "$region" >/dev/null

check_count() {
  local label="$1" count="$2"
  [[ "$count" =~ ^[0-9]+$ ]] || { printf '%s: respuesta AWS inválida\n' "$label" >&2; exit 2; }
  printf '%s: %s\n' "$label" "$count"
  if (( count > 0 )); then residual=1; fi
}

residual=0
check_count 'Estado Terraform' "$state_count"
check_count 'EKS' "$(aws eks list-clusters --region "$region" --query "length(clusters[?@=='$project'])" --output text)"
check_count 'VPC' "$(aws ec2 describe-vpcs --region "$region" --filters "Name=tag:Project,Values=$project" --query 'length(Vpcs)' --output text)"
check_count 'Instancias EC2 activas' "$(aws ec2 describe-instances --region "$region" --filters "Name=tag:Project,Values=$project" "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" --query 'length(Reservations[].Instances[])' --output text)"
check_count 'Volúmenes EBS' "$(aws ec2 describe-volumes --region "$region" --filters "Name=tag:Project,Values=$project" --query 'length(Volumes)' --output text)"
check_count 'NAT gateways' "$(aws ec2 describe-nat-gateways --region "$region" --filter "Name=tag:Project,Values=$project" --query 'length(NatGateways)' --output text)"
check_count 'IPv4 elásticas' "$(aws ec2 describe-addresses --region "$region" --filters "Name=tag:Project,Values=$project" --query 'length(Addresses)' --output text)"
check_count 'Repositorios ECR' "$(aws ecr describe-repositories --region "$region" --query "length(repositories[?starts_with(repositoryName, '$project/')])" --output text)"
check_count 'Bucket S3' "$(aws s3api list-buckets --region "$region" --query "length(Buckets[?starts_with(Name, '$project-') && ends_with(Name, '-$region-snapshots')])" --output text)"
check_count 'Logs EKS' "$(aws logs describe-log-groups --region "$region" --log-group-name-prefix "/aws/eks/$project/" --query 'length(logGroups)' --output text)"
check_count 'Balanceadores clásicos' "$(aws elb describe-load-balancers --region "$region" --query "length(LoadBalancerDescriptions[?starts_with(LoadBalancerName, '$project')])" --output text)"
check_count 'Balanceadores v2' "$(aws elbv2 describe-load-balancers --region "$region" --query "length(LoadBalancers[?starts_with(LoadBalancerName, '$project')])" --output text)"
if (( residual > 0 )); then
  printf 'Quedan recursos o estado de la PoC; revisar y repetir la limpieza\n' >&2
  exit 1
fi
printf 'Sin recursos residuales detectados para %s en %s\n' "$project" "$region"

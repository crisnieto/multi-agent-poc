#!/usr/bin/env bash
set -euo pipefail

# Invocar solo tras una instrucción explícita de iniciar una ventana AWS.
[[ "${POC_DEPLOY_APPROVED:-}" == 1 ]] || { printf 'Falta POC_DEPLOY_APPROVED=1; no se crearán recursos AWS\n' >&2; exit 2; }
root="$(cd "$(dirname "$0")/../.." && pwd)"
[[ -n "${POC_AWS_REGION:-}" && -n "${POC_TFVARS:-}" && -f "$POC_TFVARS" && -n "${POC_PRICE_FILE:-}" && -f "$POC_PRICE_FILE" ]] || {
  printf 'Configurar POC_AWS_REGION, POC_TFVARS y POC_PRICE_FILE\n' >&2; exit 2;
}
[[ -n "${OPENAI_API_KEY:-}" && -n "${POC_OPERATOR_PASSWORD:-}" ]] || {
  printf 'Faltan las credenciales de ejecución en el entorno\n' >&2; exit 2;
}
POC_TFVARS="$(cd "$(dirname "$POC_TFVARS")" && pwd)/$(basename "$POC_TFVARS")"
POC_PRICE_FILE="$(cd "$(dirname "$POC_PRICE_FILE")" && pwd)/$(basename "$POC_PRICE_FILE")"
export POC_TFVARS POC_PRICE_FILE
for binary in aws terraform kubectl docker go node; do command -v "$binary" >/dev/null || { printf 'Falta %s\n' "$binary" >&2; exit 2; }; done
for report in local-components.md local-integration.md; do
  [[ -s "$root/infra/reports/$report" ]] || { printf 'Falta gate local: %s\n' "$report" >&2; exit 2; }
  grep -qi 'PASS' "$root/infra/reports/$report" || { printf 'Gate local sin PASS: %s\n' "$report" >&2; exit 2; }
done
[[ -x "$root/infra/scripts/destroy.sh" && -x "$root/infra/scripts/audit-residuals.sh" && -x "$root/infra/scripts/stop-timer.sh" ]] || {
  printf 'Faltan controles de cierre\n' >&2; exit 2;
}

"$root/infra/scripts/preflight-eks.sh"
"$root/infra/scripts/preflight-budget.sh"
tf_dir="$root/infra/terraform"
terraform -chdir="$tf_dir" init -input=false >/dev/null
mkdir -p "$root/infra/.runtime/aws"
plan="$root/infra/.runtime/aws/poc.tfplan"
terraform -chdir="$tf_dir" plan -input=false -var-file="$POC_TFVARS" -out="$plan"
terraform -chdir="$tf_dir" show -json "$plan" |
  node -e 'let s="";process.stdin.on("data",x=>s+=x).on("end",()=>{
    const p=JSON.parse(s),v=p.variables||{},rates=JSON.parse(require("fs").readFileSync(process.env.POC_PRICE_FILE));
    const value=k=>v[k]?.value;
    if(value("aws_region")!==rates.region||value("node_count")!==rates.node_count||value("window_hours")!==rates.hours||
       value("public_access_enabled")!==rates.public_access_enabled||
       value("worker_replicas")!==2||rates.hours!==2){
      console.error("Plan Terraform y estimación no coinciden o la ventana supera 2 horas");process.exit(1)
    }
    if(!p.resource_changes?.some(x=>x.type==="aws_budgets_budget"&&x.change.actions.includes("create"))){
      console.error("El plan no crea el presupuesto AWS Budgets");process.exit(1)
    }
  })'

applied=0
timer_armed=0
cleanup_on_error() {
  status=$?
  if (( status != 0 && timer_armed == 1 )); then
    "$root/infra/scripts/stop-timer.sh" disarm || true
  fi
  if (( status != 0 && applied == 1 )); then
    printf 'Despliegue fallido; destruyendo la ventana AWS\n' >&2
    "$root/infra/scripts/destroy.sh" || printf 'La limpieza automática falló; ejecutar destroy.sh y auditar residuos de inmediato\n' >&2
  fi
  exit "$status"
}
trap cleanup_on_error EXIT
deadline="$(node -e 'console.log(new Date(Date.now()+2*3600000).toISOString())')"
"$root/infra/scripts/stop-timer.sh" arm-until "$deadline"
timer_armed=1
applied=1
terraform -chdir="$tf_dir" apply -input=false -auto-approve "$plan"
"$root/infra/scripts/install-substrate.sh"
"$root/infra/scripts/build-push.sh"
"$root/infra/scripts/deploy-apps.sh"
trap - EXIT
printf 'Ventana AWS activa. Ejecutar smoke-app.sh y luego destroy.sh antes del plazo de 2 horas.\n'

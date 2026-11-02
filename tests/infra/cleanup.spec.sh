#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/terraform"
cat >"$fixture/bin/aws" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-} ${2:-}" == 'sts get-caller-identity' ]]; then exit 0; fi
if [[ "${1:-} ${2:-}" == 'eks describe-cluster' ]]; then exit 1; fi
if [[ "${1:-} ${2:-}" == 'ec2 describe-volumes' && "${MOCK_EBS_RESIDUAL:-0}" == 1 ]]; then printf '1\n'; exit 0; fi
printf '0\n'
MOCK
cat >"$fixture/bin/terraform" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case " $* " in
  *' state list '*) exit 0;;
  *' output -raw aws_region '*) printf 'us-east-1\n';;
  *' output -raw cluster_name '*) printf 'substrate-poc\n';;
  *' destroy '*) printf 'mock destroy\n';;
  *) exit 9;;
esac
MOCK
chmod +x "$fixture/bin/aws" "$fixture/bin/terraform"
export PATH="$fixture/bin:$PATH"
export POC_TERRAFORM_DIR="$fixture/terraform"
export POC_AWS_REGION=us-east-1
export POC_PROJECT_NAME=substrate-poc
export POC_TFVARS="$fixture/window.tfvars"
touch "$POC_TFVARS"

if "$root/infra/scripts/audit-residuals.sh" >"$fixture/out" 2>&1; then
  printf 'FAIL: auditoría aceptó estado ausente\n' >&2; exit 1
fi
touch "$POC_TERRAFORM_DIR/terraform.tfstate"
"$root/infra/scripts/audit-residuals.sh" >"$fixture/out"
if MOCK_EBS_RESIDUAL=1 "$root/infra/scripts/audit-residuals.sh" >"$fixture/out" 2>&1; then
  printf 'FAIL: auditoría aceptó EBS residual\n' >&2; exit 1
fi
if POC_PROJECT_NAME=wrong-project "$root/infra/scripts/destroy.sh" >"$fixture/out" 2>&1; then
  printf 'FAIL: destroy aceptó proyecto distinto\n' >&2; exit 1
fi
"$root/infra/scripts/destroy.sh" >"$fixture/out"
printf 'PASS: cleanup falla cerrado y acepta estado limpio simulado\n'

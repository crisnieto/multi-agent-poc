#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for command in aws node; do command -v "$command" >/dev/null || { printf 'Falta %s en PATH\n' "$command" >&2; exit 2; }; done
prices="${POC_PRICE_FILE:-}"
[[ -n "$prices" && -f "$prices" ]] || { printf 'Configurar POC_PRICE_FILE con tarifas regionales verificadas\n' >&2; exit 2; }
[[ -n "${POC_AWS_REGION:-}" ]] || { printf 'Configurar POC_AWS_REGION\n' >&2; exit 2; }
configured_region="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).region)' "$prices")"
[[ "$configured_region" == "$POC_AWS_REGION" ]] || { printf 'La región de tarifas no coincide con POC_AWS_REGION\n' >&2; exit 2; }
[[ -n "${POC_PRIOR_OPENAI_SPEND_USD:-}" ]] || { printf 'Configurar POC_PRIOR_OPENAI_SPEND_USD según OpenAI Billing\n' >&2; exit 2; }
[[ -n "${POC_OPENAI_SPEND_AS_OF_UTC:-}" ]] || { printf 'Configurar POC_OPENAI_SPEND_AS_OF_UTC con la hora de lectura de Billing\n' >&2; exit 2; }
node -e 'const t=new Date(process.env.POC_OPENAI_SPEND_AS_OF_UTC).getTime();if(!Number.isFinite(t)||t>Date.now()||Date.now()-t>24*3600*1000)process.exit(1)' || {
  printf 'La lectura de gasto OpenAI debe ser de las últimas 24 horas\n' >&2; exit 2;
}
aws sts get-caller-identity --region us-east-1 >/dev/null
period="$(node -e 'const d=new Date();const start=new Date(Date.UTC(d.getUTCFullYear(),d.getUTCMonth(),1));const end=new Date(Date.UTC(d.getUTCFullYear(),d.getUTCMonth()+1,1));console.log(`Start=${start.toISOString().slice(0,10)},End=${end.toISOString().slice(0,10)}`)')"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
aws ce get-cost-and-usage --region us-east-1 --time-period "$period" --granularity MONTHLY --metrics UnblendedCost --output json >"$tmp"
aws_spend="$(node - "$tmp" <<'NODE'
const fs = require('fs');
const data = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const amount = data.ResultsByTime?.[0]?.Total?.UnblendedCost;
if (!amount || amount.Unit !== 'USD' || !Number.isFinite(Number(amount.Amount))) process.exit(1);
console.log(Number(amount.Amount));
NODE
)" || { printf 'Cost Explorer no devolvió gasto mensual verificable\n' >&2; exit 2; }
POC_PRIOR_AWS_SPEND_USD="$aws_spend" "$ROOT/apps/control-plane/node_modules/.bin/tsx" "$ROOT/infra/scripts/cost-estimate.ts" "$prices"

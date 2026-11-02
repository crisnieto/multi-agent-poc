import { readFileSync } from 'node:fs';

const rateKeys = [
  'eks_cluster_hour', 'ec2_node_hour', 'public_ipv4_hour', 'nlb_hour', 'nlcu_hour', 'ebs_gib_month',
  's3_gib_month', 's3_requests_per_1000', 'ecr_gib_month',
  'cloudwatch_ingest_gib', 'cloudwatch_storage_gib_month', 'internet_transfer_gib',
  'openai_input_million', 'openai_output_million',
] as const;
type RateKey = typeof rateKeys[number];
type Rates = Record<RateKey, number>;
type Sources = Record<RateKey, string>;

export type CostInput = {
  region: string;
  priced_at: string;
  hours: number;
  node_count: number;
  public_ipv4_count: number;
  public_access_enabled: boolean;
  budget_usd: number;
  reserve_fraction: number;
  prior_aws_usd: number;
  prior_openai_usd: number;
  rates: Rates;
  sources: Sources;
  usage: {
    ebs_gib: number; s3_gib: number; s3_requests: number; ecr_gib: number;
    cloudwatch_ingest_gib: number; cloudwatch_storage_gib: number;
    internet_transfer_gib: number; openai_input_tokens: number; openai_output_tokens: number;
    misc_buffer_usd: number; nlcu_per_hour: number;
  };
};

function nonnegative(value: unknown, path: string): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) throw new Error(`Tarifa o uso faltante/inválido: ${path}`);
  return value;
}

export function estimate(input: CostInput, now = new Date()) {
  if (!/^[a-z]{2}-[a-z]+-\d$/.test(input.region)) throw new Error('Región AWS inválida');
  const pricedAt = new Date(input.priced_at);
  if (!Number.isFinite(pricedAt.getTime()) || pricedAt > now || now.getTime() - pricedAt.getTime() > 7 * 86_400_000) {
    throw new Error('Tarifas sin fecha reciente (máximo 7 días)');
  }
  const hours = nonnegative(input.hours, 'hours');
  if (hours <= 0 || hours > 730) throw new Error('La ventana debe durar entre 0 y 730 horas');
  const nodes = nonnegative(input.node_count, 'node_count');
  if (!Number.isInteger(nodes) || nodes < 1) throw new Error('Se necesita al menos un nodo entero');
  const ips = nonnegative(input.public_ipv4_count, 'public_ipv4_count');
  if (!Number.isInteger(ips)) throw new Error('public_ipv4_count debe ser entero');
  if (typeof input.public_access_enabled !== 'boolean' || ips !== (input.public_access_enabled ? 3 : 1)) {
    throw new Error('Acceso público y cantidad de IPv4 no coinciden');
  }
  const budget = nonnegative(input.budget_usd, 'budget_usd');
  if (budget <= 0 || budget > 80) throw new Error('El presupuesto de esta PoC no puede superar USD 80');
  const reserve = nonnegative(input.reserve_fraction, 'reserve_fraction');
  if (reserve < 0.2 || reserve >= 1) throw new Error('La reserva debe ser al menos 20 %');
  const priorAws = nonnegative(input.prior_aws_usd, 'prior_aws_usd');
  const priorOpenai = nonnegative(input.prior_openai_usd, 'prior_openai_usd');
  for (const key of rateKeys) {
    nonnegative(input.rates?.[key], `rates.${key}`);
    if (!/^https:\/\//.test(input.sources?.[key] ?? '')) throw new Error(`Fuente de tarifa faltante: sources.${key}`);
  }
  const usage = input.usage;
  for (const [key, value] of Object.entries(usage ?? {})) nonnegative(value, `usage.${key}`);
  const requiredUsage = [
    'ebs_gib', 's3_gib', 's3_requests', 'ecr_gib', 'cloudwatch_ingest_gib',
    'cloudwatch_storage_gib', 'internet_transfer_gib', 'openai_input_tokens',
    'openai_output_tokens', 'misc_buffer_usd', 'nlcu_per_hour',
  ];
  for (const key of requiredUsage) nonnegative(usage?.[key as keyof typeof usage], `usage.${key}`);
  const r = input.rates;
  const monthFraction = hours / 730;
  const hourly = hours * (r.eks_cluster_hour + nodes * r.ec2_node_hour + ips * r.public_ipv4_hour +
    (input.public_access_enabled ? r.nlb_hour + usage.nlcu_per_hour * r.nlcu_hour : 0));
  const storage = monthFraction * (usage.ebs_gib * r.ebs_gib_month + usage.s3_gib * r.s3_gib_month +
    usage.ecr_gib * r.ecr_gib_month + usage.cloudwatch_storage_gib * r.cloudwatch_storage_gib_month);
  const variable = usage.s3_requests / 1000 * r.s3_requests_per_1000 +
    usage.cloudwatch_ingest_gib * r.cloudwatch_ingest_gib + usage.internet_transfer_gib * r.internet_transfer_gib;
  const openai = usage.openai_input_tokens / 1_000_000 * r.openai_input_million +
    usage.openai_output_tokens / 1_000_000 * r.openai_output_million;
  const estimated = hourly + storage + variable + openai + usage.misc_buffer_usd;
  const projected = priorAws + priorOpenai + estimated;
  const limit = budget * (1 - reserve);
  return {
    approved: projected <= limit,
    region: input.region, hours, priced_at: input.priced_at,
    prior_usd: priorAws + priorOpenai,
    window_usd: Number(estimated.toFixed(4)), projected_usd: Number(projected.toFixed(4)),
    limit_with_reserve_usd: Number(limit.toFixed(4)),
    remaining_before_reserve_usd: Number((limit - projected).toFixed(4)),
    breakdown_usd: { hourly: Number(hourly.toFixed(4)), storage: Number(storage.toFixed(4)),
      variable: Number(variable.toFixed(4)), openai: Number(openai.toFixed(4)), misc: usage.misc_buffer_usd },
  };
}

if (process.argv[1]?.endsWith('cost-estimate.ts')) {
  try {
    const path = process.argv[2];
    if (!path) throw new Error('Uso: cost-estimate.ts <archivo-json>');
    const input = JSON.parse(readFileSync(path, 'utf8')) as CostInput;
    if (process.env.POC_PRIOR_AWS_SPEND_USD !== undefined) input.prior_aws_usd = Number(process.env.POC_PRIOR_AWS_SPEND_USD);
    if (process.env.POC_PRIOR_OPENAI_SPEND_USD !== undefined) input.prior_openai_usd = Number(process.env.POC_PRIOR_OPENAI_SPEND_USD);
    const result = estimate(input);
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    if (!result.approved) process.exitCode = 1;
  } catch (error) {
    process.stderr.write(`${(error as Error).message}\n`);
    process.exitCode = 2;
  }
}

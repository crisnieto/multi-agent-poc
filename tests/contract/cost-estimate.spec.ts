import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { estimate, type CostInput } from '../../infra/scripts/cost-estimate.js';

const input = JSON.parse(readFileSync(resolve(import.meta.dirname, '../../infra/config/prices.example.json'), 'utf8')) as CostInput;
Object.assign(input.rates, {
  ebs_gib_month: 0.08, s3_gib_month: 0.023, s3_requests_per_1000: 0.005,
  ecr_gib_month: 0.10, cloudwatch_ingest_gib: 0.50,
  cloudwatch_storage_gib_month: 0.03, internet_transfer_gib: 0.09,
});
const now = new Date('2026-11-02T12:00:00Z');
const short = estimate(input, now);
assert(short.approved, 'Una ventana de 48 horas debe caber en la reserva');
assert(short.projected_usd < 64);

const continuous = structuredClone(input);
continuous.hours = 730;
assert(!estimate(continuous, now).approved, 'EKS continuo debe rechazarse con USD 80');

const missing = structuredClone(input);
(missing.rates as Record<string, unknown>).ebs_gib_month = null;
assert.throws(() => estimate(missing, now), /Tarifa o uso faltante/);

const prior = structuredClone(input);
prior.prior_aws_usd = 60;
assert(!estimate(prior, now).approved, 'Gasto previo debe reducir saldo');

const stale = structuredClone(input);
stale.priced_at = '2026-10-01T00:00:00Z';
assert.throws(() => estimate(stale, now), /fecha reciente/);
console.log('Contrato financiero PASS: ventana viable, 730 horas, tarifa faltante, gasto previo y antigüedad');

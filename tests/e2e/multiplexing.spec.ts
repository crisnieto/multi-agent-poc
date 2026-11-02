import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { spawn } from 'node:child_process';
import { promisify } from 'node:util';

const exec = promisify(execFile);
const root = resolve(import.meta.dirname, '../..');
const cli = join(root, 'infra/.cache/kubectl-ate');
const port = 18084;
const base = `http://127.0.0.1:${port}/api`;
const testPassword = 'local-multiplex-test';
const markers = ['nutria', 'carpincho', 'ajolote'];
const startedAt = new Date();
type Session = { id: string; actor_id: string };
type Request = { id: string; status: string; final_text?: string; error_code?: string };
type Actor = { status?: { state?: string; workerAssignment?: { worker?: { name?: string } } } };

async function ate(args: string[]): Promise<string> {
  const result = await exec(cli, args, { timeout: 120_000, maxBuffer: 2 * 1024 * 1024 });
  return result.stdout;
}

async function actor(id: string): Promise<Actor> {
  return JSON.parse(await ate(['get', 'actor', id, '-a', 'ate-demo-counter', '-o', 'json'])) as Actor;
}

async function waitState(id: string, state: string): Promise<Actor> {
  for (let i = 0; i < 60; i++) {
    const current = await actor(id);
    if (current.status?.state === state) return current;
    await delay(500);
  }
  throw new Error(`actor_state_timeout:${state}`);
}

async function api<T>(cookie: string, path: string, options?: RequestInit): Promise<T> {
  const response = await fetch(`${base}${path}`, { ...options, headers: { cookie, ...(options?.body ? { 'content-type': 'application/json' } : {}), ...options?.headers } });
  if (!response.ok) throw new Error(`api_${response.status}:${path}`);
  return response.json() as Promise<T>;
}

async function turn(cookie: string, session: Session, prompt: string): Promise<Request> {
  const request = await api<Request>(cookie, `/sessions/${session.id}/requests`, { method: 'POST', body: JSON.stringify({ text: prompt }) });
  for (let i = 0; i < 300; i++) {
    const current = await api<Request>(cookie, `/requests/${request.id}`);
    if (current.status === 'completed') return current;
    if (current.status === 'failed') throw new Error(`turn_failed:${current.error_code ?? 'unknown'}`);
    await delay(500);
  }
  throw new Error('turn_timeout');
}

const dir = await mkdtemp(join(tmpdir(), 'poc-multiplex-'));
const server = spawn(process.execPath, [join(root, 'apps/control-plane/dist/server.js')], {
  cwd: join(root, 'apps/control-plane'), stdio: 'ignore',
  env: { ...process.env, OPENAI_API_KEY: '', POC_DB_PATH: join(dir, 'poc.sqlite'), POC_PORT: String(port),
    POC_OPERATOR_PASSWORD: testPassword, POC_SUBSTRATE_MODE: 'real', POC_IDLE_SECONDS: '600',
    POC_ATE_CLI: cli, POC_EGRESS_POLICY_PATH: join(root, 'infra/local/egress-policy.yaml') },
});
const sessions: Session[] = [];
try {
  let ready = false;
  for (let i = 0; i < 50; i++) {
    try { const response = await fetch(`${base}/healthz`); if (response.ok) { ready = true; break; } }
    catch { /* Startup. */ }
    await delay(100);
  }
  assert(ready, 'API no inició');
  const login = await fetch(`${base}/auth/login`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ password: testPassword }) });
  assert.equal(login.status, 204);
  const cookie = login.headers.get('set-cookie')?.split(';')[0] ?? '';
  assert(cookie.startsWith('poc_session='));
  for (let i = 0; i < 3; i++) sessions.push(await api<Session>(cookie, '/sessions', { method: 'POST' }));
  assert.equal(new Set(sessions.map((session) => session.actor_id)).size, 3);

  await Promise.all([0, 1].map((i) => turn(cookie, sessions[i]!, `Mi animal favorito de prueba es ${markers[i]}. Recuérdalo para el próximo turno. Responde solamente listo.`)));
  const first = await waitState(sessions[0]!.actor_id, 'ACTOR_STATE_RUNNING');
  const second = await waitState(sessions[1]!.actor_id, 'ACTOR_STATE_RUNNING');
  const firstWorker = first.status?.workerAssignment?.worker?.name;
  const secondWorker = second.status?.workerAssignment?.worker?.name;
  const firstPairObservedAt = new Date().toISOString();
  assert(firstWorker && secondWorker && firstWorker !== secondWorker, 'Dos actores deben ocupar workers distintos');
  await ate(['suspend', 'actor', sessions[0]!.actor_id, '-a', 'ate-demo-counter', '--mode=sync']);
  await turn(cookie, sessions[2]!, `Mi animal favorito de prueba es ${markers[2]}. Recuérdalo para el próximo turno. Responde solamente listo.`);
  const third = await waitState(sessions[2]!.actor_id, 'ACTOR_STATE_RUNNING');
  const thirdWorker = third.status?.workerAssignment?.worker?.name;
  const reuseObservedAt = new Date().toISOString();
  assert.equal(thirdWorker, firstWorker, 'El tercer actor debe reutilizar el worker liberado');
  await ate(['suspend', 'actor', sessions[1]!.actor_id, '-a', 'ate-demo-counter', '--mode=sync']);
  await ate(['suspend', 'actor', sessions[2]!.actor_id, '-a', 'ate-demo-counter', '--mode=sync']);

  const cyclesStartedAt = new Date().toISOString();
  for (let cycle = 1; cycle <= 5; cycle++) {
    for (const session of sessions) {
      await ate(['resume', 'actor', session.actor_id, '-a', 'ate-demo-counter']);
      await waitState(session.actor_id, 'ACTOR_STATE_RUNNING');
      await ate(['suspend', 'actor', session.actor_id, '-a', 'ate-demo-counter', '--mode=sync']);
      await waitState(session.actor_id, 'ACTOR_STATE_SUSPENDED');
    }
  }
  const cyclesCompletedAt = new Date().toISOString();

  for (let i = 0; i < sessions.length; i++) {
    const result = await turn(cookie, sessions[i]!, '¿Qué animal favorito de prueba mencioné antes? Responde solamente el nombre del animal.');
    const answer = result.final_text?.trim().toLowerCase() ?? '';
    assert(answer.includes(markers[i]!), `El actor ${i + 1} perdió su contexto; respondió: ${JSON.stringify(answer)}`);
    for (let other = 0; other < markers.length; other++) if (other !== i) assert(!answer.includes(markers[other]!), 'Contexto cruzado');
    await ate(['suspend', 'actor', sessions[i]!.actor_id, '-a', 'ate-demo-counter', '--mode=sync']);
  }
  console.log(JSON.stringify({ result: 'PASS', sessions: sessions.map((s) => s.id), actors: sessions.map((s) => s.actor_id),
    workers: [firstWorker, secondWorker], first_pair_observed_at: firstPairObservedAt,
    reused_worker: thirdWorker, reuse_observed_at: reuseObservedAt, cycles_per_actor: 5,
    cycles_started_at: cyclesStartedAt, cycles_completed_at: cyclesCompletedAt, context: 'isolated',
    started_at: startedAt.toISOString(), completed_at: new Date().toISOString(), duration_ms: Date.now() - startedAt.getTime() }));
} finally {
  for (const session of sessions) await ate(['delete', 'actor', session.actor_id, '-a', 'ate-demo-counter']).catch(() => undefined);
  server.kill('SIGTERM');
  await rm(dir, { recursive: true, force: true });
}

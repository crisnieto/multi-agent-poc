import assert from 'node:assert/strict';
import { execFile, spawn } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { promisify } from 'node:util';

const exec = promisify(execFile);
const root = resolve(import.meta.dirname, '../..');
const cli = join(root, 'infra/.cache/kubectl-ate');
const port = 18085;
const base = `http://127.0.0.1:${port}/api`;
const durationMs = Number(process.env.POC_SOAK_MINUTES ?? 30) * 60_000;
assert(durationMs >= 60_000, 'La prueba sostenida exige al menos un minuto');
type Session = { id: string; actor_id: string };
type Actor = { status?: { state?: string; workerAssignment?: { worker?: { name?: string } } } };

async function ate(args: string[]) { return (await exec(cli, args, { timeout: 120_000 })).stdout; }
async function actor(id: string): Promise<Actor> { return JSON.parse(await ate(['get', 'actor', id, '-a', 'ate-demo-counter', '-o', 'json'])) as Actor; }

async function wake(id: string, localPort: number): Promise<string> {
  const proxy = spawn(cli, ['proxy', 'actor', id, `${localPort}:8090`, '-a', 'ate-demo-counter'], { stdio: 'ignore' });
  let failed = false;
  proxy.on('error', () => { failed = true; });
  try {
    let ready = false;
    for (let i = 0; i < 60; i++) {
      if (failed || proxy.exitCode !== null) throw new Error('proxy_failed');
      try { const r = await fetch(`http://127.0.0.1:${localPort}/healthz`, { signal: AbortSignal.timeout(1000) }); if (r.ok) { ready = true; break; } }
      catch { /* Startup. */ }
      await delay(250);
    }
    assert(ready, 'Actor no respondió en el router');
    const current = await actor(id);
    assert.equal(current.status?.state, 'ACTOR_STATE_RUNNING');
    const worker = current.status?.workerAssignment?.worker?.name;
    assert(worker, 'Asignación no observada');
    return worker;
  } finally { proxy.kill('SIGTERM'); }
}

const dir = await mkdtemp(join(tmpdir(), 'poc-soak-'));
const server = spawn(process.execPath, [join(root, 'apps/control-plane/dist/server.js')], {
  cwd: join(root, 'apps/control-plane'), stdio: 'ignore',
  env: { ...process.env, OPENAI_API_KEY: '', POC_DB_PATH: join(dir, 'poc.sqlite'), POC_PORT: String(port),
    POC_OPERATOR_PASSWORD: 'local-soak-test', POC_SUBSTRATE_MODE: 'real', POC_IDLE_SECONDS: '3600', POC_ATE_CLI: cli },
});
const sessions: Session[] = [];
try {
  let ready = false;
  for (let i = 0; i < 50; i++) {
    try { if ((await fetch(`${base}/healthz`)).ok) { ready = true; break; } } catch { /* Startup. */ }
    await delay(100);
  }
  assert(ready, 'API no inició');
  const login = await fetch(`${base}/auth/login`, { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ password: 'local-soak-test' }) });
  assert.equal(login.status, 204);
  const cookie = login.headers.get('set-cookie')?.split(';')[0] ?? '';
  assert(cookie.startsWith('poc_session='));
  for (let i = 0; i < 3; i++) {
    const response = await fetch(`${base}/sessions`, { method: 'POST', headers: { cookie } });
    assert.equal(response.status, 201);
    sessions.push(await response.json() as Session);
  }
  const startedAt = new Date();
  let iteration = 0;
  while (true) {
    const first = await wake(sessions[0]!.actor_id, 18100);
    const second = await wake(sessions[1]!.actor_id, 18101);
    assert.notEqual(first, second, 'Dos actores activos requieren workers distintos');
    await ate(['suspend', 'actor', sessions[0]!.actor_id, '-a', 'ate-demo-counter', '--mode=sync']);
    const third = await wake(sessions[2]!.actor_id, 18102);
    assert.equal(third, first, 'No se reutilizó el worker liberado');
    const topologyResponse = await fetch(`${base}/topology`, { headers: { cookie } });
    assert.equal(topologyResponse.status, 200);
    const topology = await topologyResponse.json() as { actors: Array<{ actor_id: string; worker_id?: string }>; workers: Array<{ worker_id: string; state: string }> };
    assert.equal(topology.actors.find((item) => item.actor_id === sessions[2]!.actor_id)?.worker_id, third);
    assert.equal(topology.workers.filter((item) => item.state === 'busy').length, 2);
    await ate(['suspend', 'actor', sessions[1]!.actor_id, '-a', 'ate-demo-counter', '--mode=sync']);
    await ate(['suspend', 'actor', sessions[2]!.actor_id, '-a', 'ate-demo-counter', '--mode=sync']);
    const now = new Date();
    console.log(JSON.stringify({ type: 'sample', iteration: ++iteration, observed_at: now.toISOString(),
      first_actor: sessions[0]!.actor_id, reused_by: sessions[2]!.actor_id, reused_worker: third,
      other_worker: second, elapsed_ms: now.getTime() - startedAt.getTime() }));
    const remaining = durationMs - (Date.now() - startedAt.getTime());
    if (remaining <= 0) break;
    await delay(Math.min(300_000, remaining));
  }
  console.log(JSON.stringify({ type: 'result', result: 'PASS', started_at: startedAt.toISOString(),
    completed_at: new Date().toISOString(), duration_ms: Date.now() - startedAt.getTime(),
    sessions: sessions.map((session) => session.id), samples: iteration, openai_calls: 0 }));
} finally {
  for (const session of sessions) await ate(['delete', 'actor', session.actor_id, '-a', 'ate-demo-counter']).catch(() => undefined);
  server.kill('SIGTERM');
  await rm(dir, { recursive: true, force: true });
}

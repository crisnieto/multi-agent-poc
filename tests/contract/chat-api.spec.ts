import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { canTransition, terminal } from '../../apps/control-plane/src/requests/model.js';

const root = resolve(import.meta.dirname, '../..');
const dir = await mkdtemp(join(tmpdir(), 'poc-chat-contract-'));
const port = 18086;
const base = `http://127.0.0.1:${port}/api`;
const server = spawn(process.execPath, [join(root, 'apps/control-plane/dist/server.js')], {
  cwd: join(root, 'apps/control-plane'), stdio: 'ignore',
  env: { ...process.env, POC_DB_PATH: join(dir, 'poc.sqlite'), POC_PORT: String(port),
    POC_OPERATOR_PASSWORD: 'local-contract-test', POC_SUBSTRATE_MODE: 'mock' },
});
try {
  assert(canTransition('queued', 'running'));
  assert(canTransition('running', 'completed'));
  assert(!canTransition('completed', 'running'));
  assert(terminal('timed_out') && terminal('cancelled'));
  let ready = false;
  for (let i = 0; i < 50; i++) {
    try { if ((await fetch(`${base}/healthz`)).ok) { ready = true; break; } } catch { /* Startup. */ }
    await delay(100);
  }
  assert(ready, 'API no inició');
  assert.equal((await fetch(`${base}/sessions`)).status, 401);
  const login = await fetch(`${base}/auth/login`, { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ password: 'local-contract-test' }) });
  assert.equal(login.status, 204);
  const cookie = login.headers.get('set-cookie')?.split(';')[0] ?? '';
  assert(cookie.startsWith('poc_session='));
  const sessionResponse = await fetch(`${base}/sessions`, { method: 'POST', headers: { cookie } });
  assert.equal(sessionResponse.status, 201);
  const session = await sessionResponse.json() as { id: string; actor_id: string };
  assert(session.actor_id.startsWith('mock-'));
  const invalid = await fetch(`${base}/sessions/${session.id}/requests`, { method: 'POST',
    headers: { cookie, 'content-type': 'application/json' }, body: JSON.stringify({ text: '' }) });
  assert.equal(invalid.status, 400);
  const accepted = await fetch(`${base}/sessions/${session.id}/requests`, { method: 'POST',
    headers: { cookie, 'content-type': 'application/json' }, body: JSON.stringify({ text: 'hola' }) });
  assert.equal(accepted.status, 202);
  const request = await accepted.json() as { id: string; status: string };
  assert.equal(request.status, 'completed');
  const history = await fetch(`${base}/sessions/${session.id}/messages`, { headers: { cookie } });
  assert.equal(history.status, 200);
  const turns = await history.json() as { id: string; text: string; status: string; final_text: string }[];
  assert.deepEqual(turns.map(({ id, text, status }) => ({ id, text, status })),
    [{ id: request.id, text: 'hola', status: 'completed' }]);
  assert.equal(typeof turns[0]?.final_text, 'string');
  const all = await fetch(`${base}/requests/${request.id}/events`, { headers: { cookie } });
  assert.equal(all.status, 200);
  const frames = await all.text();
  assert.equal((frames.match(/event: completed/g) ?? []).length, 1);
  assert(frames.includes('event: delta'));
  const firstId = Number(frames.match(/id: (\d+)/)?.[1]);
  assert(Number.isSafeInteger(firstId));
  const replay = await fetch(`${base}/requests/${request.id}/events`, { headers: { cookie, 'Last-Event-ID': String(firstId) } });
  assert.equal(replay.status, 200);
  const replayFrames = await replay.text();
  assert(!replayFrames.includes(`id: ${firstId}\n`));
  assert(replayFrames.includes('event: completed'));
  const badCursor = await fetch(`${base}/requests/${request.id}/events`, { headers: { cookie, 'Last-Event-ID': '-1' } });
  assert.equal(badCursor.status, 400);
  const status = await fetch(`${base}/requests/${request.id}`, { headers: { cookie } });
  assert.equal((await status.json() as { status: string }).status, 'completed');
  const closed = await fetch(`${base}/sessions/${session.id}`, { method: 'DELETE', headers: { cookie } });
  assert.equal(closed.status, 204);
  assert.equal((await fetch(`${base}/sessions/${session.id}/messages`, { headers: { cookie } })).status, 404);
  console.log('Contrato chat PASS: auth, sesión, validación, turno, SSE, replay y terminal único');
} finally {
  server.kill('SIGTERM');
  await rm(dir, { recursive: true, force: true });
}

import { randomUUID } from 'node:crypto';
import type Database from 'better-sqlite3';
import { streamActorTurn, type ActorTurnEvent } from '../actor/router-client.js';
import { appendEvent } from '../events/store.js';
import { getActor } from '../substrate/client.js';
import { canTransition, type RequestRow } from './model.js';

type SessionRow = { id: string; actor_id: string; status: string };

export class RequestConflict extends Error { constructor() { super('request_active'); } }
export class SessionMissing extends Error { constructor() { super('session_not_found'); } }

function setStatus(db: Database.Database, id: string, status: RequestRow['status'], finalText: string | null, code: string | null): void {
  const current = db.prepare('SELECT status FROM requests WHERE id = ?').get(id) as { status: RequestRow['status'] } | undefined;
  if (!current || !canTransition(current.status, status)) throw new Error('invalid_request_transition');
  db.prepare('UPDATE requests SET status = ?, final_text = ?, error_code = ?, updated_at = ? WHERE id = ?')
    .run(status, finalText, code, new Date().toISOString(), id);
}

async function runRequest(db: Database.Database, row: RequestRow, actorId: string): Promise<void> {
  let final = false;
  let accumulated = '';
  const emit = (event: ActorTurnEvent): void => {
    if (final) return;
    if (event.type === 'started') setStatus(db, row.id, 'running', null, null);
    if (event.type === 'delta') accumulated += event.text ?? '';
    if (event.type === 'completed') { final = true; setStatus(db, row.id, 'completed', event.text ?? accumulated, null); }
    if (event.type === 'failed') { final = true; setStatus(db, row.id, 'failed', null, event.code ?? 'codex_turn_failed'); }
    appendEvent(db, { requestId: row.id, sessionId: row.session_id, actorId, type: event.type,
      source: 'codex-actor', payload: { ...(event.text === undefined ? {} : { text: event.text }), ...(event.code ? { code: event.code } : {}) } });
  };
  try {
    await streamActorTurn(actorId, row.id, row.text, emit);
    if (!final) throw new Error('actor_stream_incomplete');
    try {
      const observed = await getActor(actorId);
      appendEvent(db, { requestId: row.id, sessionId: row.session_id, actorId,
        workerId: observed.status?.workerAssignment?.worker?.name ?? null,
        type: 'actor.observed', source: 'substrate', payload: { state: observed.status?.state ?? 'unknown' } });
    } catch { /* A missing observation must not change a completed turn. */ }
  } catch {
    if (!final) emit({ type: 'failed', code: 'actor_unavailable' });
  } finally {
    db.prepare('UPDATE sessions SET status = ?, updated_at = ? WHERE id = ? AND status != ?')
      .run('ready', new Date().toISOString(), row.session_id, 'closed');
  }
}

export function startRequest(db: Database.Database, sessionId: string, text: string, idempotencyKey?: string): RequestRow {
  const session = db.prepare('SELECT id, actor_id, status FROM sessions WHERE id = ? AND status != ?').get(sessionId, 'closed') as SessionRow | undefined;
  if (!session) throw new SessionMissing();
  if (idempotencyKey) {
    const existing = db.prepare(`SELECT r.* FROM request_keys k JOIN requests r ON r.id = k.request_id
      WHERE k.session_id = ? AND k.idempotency_key = ?`).get(sessionId, idempotencyKey) as RequestRow | undefined;
    if (existing) return existing;
  }
  const active = db.prepare("SELECT 1 FROM requests WHERE session_id = ? AND status IN ('queued','running') LIMIT 1").get(sessionId);
  if (active) throw new RequestConflict();
  const now = new Date().toISOString();
  const row: RequestRow = { id: randomUUID(), session_id: sessionId, text, status: 'queued', final_text: null, error_code: null, created_at: now, updated_at: now };
  db.transaction(() => {
    db.prepare('INSERT INTO requests VALUES (@id, @session_id, @text, @status, @final_text, @error_code, @created_at, @updated_at)').run(row);
    if (idempotencyKey) db.prepare('INSERT INTO request_keys VALUES (?, ?, ?)').run(sessionId, idempotencyKey, row.id);
    db.prepare('UPDATE sessions SET status = ?, updated_at = ? WHERE id = ?').run('busy', now, sessionId);
    appendEvent(db, { requestId: row.id, sessionId, actorId: session.actor_id, type: 'queued', source: 'control-plane', payload: {} });
  })();
  void runRequest(db, row, session.actor_id);
  return row;
}

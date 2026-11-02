import { randomUUID } from 'node:crypto';
import type Database from 'better-sqlite3';
import type { FastifyInstance } from 'fastify';
import { mockAnswer } from '../adapters/mock.js';
import { sendSse, startSse, waitForDrain } from '../events/sse.js';
import { startRequest, RequestConflict, SessionMissing } from '../requests/service.js';
import { terminal } from '../requests/model.js';
import { setTimeout as delay } from 'node:timers/promises';

type RequestRow = { id: string; session_id: string; text: string; status: string; final_text: string | null; error_code: string | null; created_at: string; updated_at: string };
type EventRow = { id: number; type: string; payload: string };

export function registerRequests(app: FastifyInstance, db: Database.Database): void {
  const real = process.env.POC_SUBSTRATE_MODE === 'real';
  app.post<{ Params: { sessionId: string }; Body: { text?: unknown; idempotency_key?: unknown } }>('/api/sessions/:sessionId/requests', async (request, reply) => {
    const session = db.prepare('SELECT id FROM sessions WHERE id = ? AND status != ?').get(request.params.sessionId, 'closed');
    if (!session) return reply.code(404).send({ error: 'session_not_found' });
    if (typeof request.body?.text !== 'string' || !request.body.text.trim() || request.body.text.length > 16000) {
      return reply.code(400).send({ error: 'invalid_text' });
    }
    const key = request.body.idempotency_key;
    if (key !== undefined && (typeof key !== 'string' || !key.trim() || key.length > 128)) {
      return reply.code(400).send({ error: 'invalid_idempotency_key' });
    }
    if (real) {
      try { return reply.code(202).send({ ...startRequest(db, request.params.sessionId, request.body.text, key as string | undefined), source: 'substrate' }); }
      catch (error) {
        if (error instanceof SessionMissing) return reply.code(404).send({ error: error.message });
        if (error instanceof RequestConflict) return reply.code(409).send({ error: error.message });
        throw error;
      }
    }
    const now = new Date().toISOString();
    const row: RequestRow = { id: randomUUID(), session_id: request.params.sessionId, text: request.body.text, status: 'completed', final_text: mockAnswer(request.body.text), error_code: null, created_at: now, updated_at: now };
    db.prepare('INSERT INTO requests VALUES (@id, @session_id, @text, @status, @final_text, @error_code, @created_at, @updated_at)').run(row);
    const actor = db.prepare('SELECT actor_id FROM sessions WHERE id = ?').get(row.session_id) as { actor_id: string };
    const insert = db.prepare('INSERT INTO events (request_id, session_id, actor_id, worker_id, type, source, payload, observed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
    for (const [type, payload] of [
      ['queued', {}], ['started', { worker_id: 'mock-worker-1' }],
      ['delta', { text: row.final_text }], ['completed', { text: row.final_text }],
    ] as const) insert.run(row.id, row.session_id, actor.actor_id, 'mock-worker-1', type, 'mock', JSON.stringify({ ...payload, source: 'mock' }), now);
    return reply.code(202).send({ ...row, source: 'mock' });
  });
  app.get<{ Params: { requestId: string } }>('/api/requests/:requestId', async (request, reply) => {
    const row = db.prepare('SELECT * FROM requests WHERE id = ?').get(request.params.requestId);
    return row ? { ...(row as object), source: real ? 'substrate' : 'mock' } : reply.code(404).send({ error: 'not_found' });
  });
  app.get<{ Params: { requestId: string } }>('/api/requests/:requestId/events', async (request, reply) => {
    const row = db.prepare('SELECT id FROM requests WHERE id = ?').get(request.params.requestId);
    if (!row) return reply.code(404).send({ error: 'not_found' });
    const rawAfter = request.headers['last-event-id'];
    if (rawAfter !== undefined && (typeof rawAfter !== 'string' || !/^\d+$/.test(rawAfter) || !Number.isSafeInteger(Number(rawAfter)))) {
      return reply.code(400).send({ error: 'invalid_last_event_id' });
    }
    const after = Number(rawAfter ?? 0);
    startSse(reply);
    let cursor = after;
    let lastHeartbeat = Date.now();
    do {
      const events = db.prepare('SELECT id, type, payload FROM events WHERE request_id = ? AND id > ? ORDER BY id').all(request.params.requestId, cursor) as EventRow[];
      for (const event of events) {
        if (!sendSse(reply, event.id, event.type, JSON.parse(event.payload))) await waitForDrain(reply);
        cursor = event.id;
        if (reply.raw.destroyed) break;
      }
      if (!real || reply.raw.destroyed) break;
      const status = (db.prepare('SELECT status FROM requests WHERE id = ?').get(request.params.requestId) as { status: string }).status;
      if (terminal(status)) break;
      if (Date.now() - lastHeartbeat > 15000) {
        if (!reply.raw.write(': heartbeat\n\n')) await waitForDrain(reply);
        lastHeartbeat = Date.now();
      }
      await delay(250);
    } while (!reply.raw.destroyed);
    reply.raw.end();
  });
}

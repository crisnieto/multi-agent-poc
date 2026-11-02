import type Database from 'better-sqlite3';

export function appendEvent(db: Database.Database, input: {
  requestId: string; sessionId: string; actorId: string; workerId?: string | null;
  type: string; source: string; payload: Record<string, unknown>;
}): number {
  const result = db.prepare(`INSERT INTO events
    (request_id, session_id, actor_id, worker_id, type, source, payload, observed_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)`).run(
    input.requestId, input.sessionId, input.actorId, input.workerId ?? null,
    input.type, input.source, JSON.stringify(input.payload), new Date().toISOString(),
  );
  return Number(result.lastInsertRowid);
}

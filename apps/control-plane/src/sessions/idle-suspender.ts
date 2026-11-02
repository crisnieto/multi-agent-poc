import type Database from 'better-sqlite3';
import { getActor, suspendActor } from '../substrate/client.js';

type IdleSession = { id: string; actor_id: string };

export function startIdleSuspender(db: Database.Database): () => void {
  const idleSeconds = Number(process.env.POC_IDLE_SECONDS ?? 60);
  if (!Number.isFinite(idleSeconds) || idleSeconds < 1) throw new Error('invalid_idle_seconds');
  let running = false;
  const tick = async () => {
    if (running) return;
    running = true;
    try {
      const cutoff = new Date(Date.now() - idleSeconds * 1000).toISOString();
      const sessions = db.prepare(`SELECT id, actor_id FROM sessions s WHERE s.status = 'ready'
        AND s.updated_at < ? AND NOT EXISTS (
          SELECT 1 FROM requests r WHERE r.session_id = s.id AND r.status IN ('queued','running'))`).all(cutoff) as IdleSession[];
      for (const session of sessions) {
        try {
          const actor = await getActor(session.actor_id);
          if (actor.status?.state !== 'ACTOR_STATE_RUNNING') continue;
          const active = db.prepare("SELECT 1 FROM requests WHERE session_id = ? AND status IN ('queued','running')").get(session.id);
          if (active) continue;
          await suspendActor(session.actor_id);
          db.prepare("UPDATE sessions SET status = 'suspended', updated_at = ? WHERE id = ? AND status = 'ready'")
            .run(new Date().toISOString(), session.id);
        } catch { /* The next tick retries transient Substrate failures. */ }
      }
    } finally { running = false; }
  };
  const timer = setInterval(() => void tick(), 5000);
  timer.unref();
  return () => clearInterval(timer);
}

import { randomUUID } from 'node:crypto';
import type Database from 'better-sqlite3';
import { configureActorEgress, createActor, deleteActor, getActor, SubstrateError } from '../substrate/client.js';

export type Session = { id: string; actor_id: string; title: string; status: string; created_at: string; updated_at: string };

export async function createSession(db: Database.Database): Promise<Session> {
  const now = new Date().toISOString();
  const id = randomUUID();
  const actorId = `poc-${id}`;
  await createActor(actorId);
  const session: Session = { id, actor_id: actorId, title: 'Nueva sesión', status: 'ready', created_at: now, updated_at: now };
  try {
    if (process.env.POC_EGRESS_POLICY_PATH) await configureActorEgress(actorId, process.env.POC_EGRESS_POLICY_PATH);
    db.prepare('INSERT INTO sessions VALUES (@id, @actor_id, @title, @status, @created_at, @updated_at)').run(session);
  } catch (error) {
    await deleteActor(actorId).catch(() => undefined);
    throw error;
  }
  return session;
}

export async function readSession(db: Database.Database, id: string): Promise<Session | null> {
  const row = db.prepare('SELECT * FROM sessions WHERE id = ? AND status != ?').get(id, 'closed') as Session | undefined;
  if (!row) return null;
  try {
    const actor = await getActor(row.actor_id);
    const state = actor.status?.state;
    const status = state === 'ACTOR_STATE_SUSPENDED' ? 'suspended' : state === 'ACTOR_STATE_RUNNING' ? 'ready' : row.status;
    return { ...row, status };
  } catch (error) {
    if (error instanceof SubstrateError && error.code === 'actor_not_found') return { ...row, status: 'failed' };
    throw error;
  }
}

export async function closeSession(db: Database.Database, id: string): Promise<boolean> {
  const row = db.prepare('SELECT * FROM sessions WHERE id = ? AND status != ?').get(id, 'closed') as Session | undefined;
  if (!row) return false;
  try { await deleteActor(row.actor_id); }
  catch (error) { if (!(error instanceof SubstrateError && error.code === 'actor_not_found')) throw error; }
  db.prepare('UPDATE sessions SET status = ?, updated_at = ? WHERE id = ?').run('closed', new Date().toISOString(), id);
  return true;
}

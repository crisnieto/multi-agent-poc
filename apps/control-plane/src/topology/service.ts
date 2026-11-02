import type Database from 'better-sqlite3';
import { listActors, listWorkers } from '../substrate/client.js';

type SessionRow = { id: string; actor_id: string };

export async function readTopology(db: Database.Database) {
  const sessions = db.prepare('SELECT id, actor_id FROM sessions WHERE status != ?').all('closed') as SessionRow[];
  const [observedActors, observedWorkers] = await Promise.all([listActors(), listWorkers()]);
  const observedAt = new Date().toISOString();
  const byName = new Map(observedActors.map((actor) => [actor.metadata?.name, actor]));
  const actors = sessions.map((session) => {
    const observed = byName.get(session.actor_id);
    const state = observed?.status?.state?.replace('ACTOR_STATE_', '').toLowerCase() ?? 'unknown';
    return { actor_id: session.actor_id, session_id: session.id, state,
      ...(observed?.status?.workerAssignment?.worker?.name ? { worker_id: observed.status.workerAssignment.worker.name } : {}),
      observed_at: observedAt, source: observed ? 'substrate' : 'unknown' };
  });
  const workers = observedWorkers.filter((worker) => worker.workerPool === 'codex-poc').map((worker) => {
    const workerId = worker.metadata?.name ?? '';
    const assigned = actors.find((actor) => 'worker_id' in actor && actor.worker_id === workerId);
    const state = worker.status?.state !== 'WORKER_STATE_ACTIVE' ? 'unavailable'
      : Number(worker.status.allocated?.actors ?? 0) > 0 ? 'busy' : 'idle';
    return { worker_id: workerId, pod_name: worker.workerPod ?? '', state,
      ...(assigned ? { actor_id: assigned.actor_id } : {}), observed_at: observedAt, source: 'substrate' };
  });
  return { observed_at: observedAt, source: 'substrate', actors, workers };
}

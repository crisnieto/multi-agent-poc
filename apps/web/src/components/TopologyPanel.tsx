import type { Topology } from '../api/client';

export function TopologyPanel({ topology }: { topology: Topology | null }) {
  return <section className="panel">
    <h2>Workers de Substrate</h2>
    <p className="muted">{topology ? `Observado: ${new Date(topology.observed_at).toLocaleTimeString()}` : 'Esperando observación de Substrate'}</p>
    <p className="muted">Ocupado significa que el worker conserva un actor asignado, aunque ya respondió. Se libera cuando el actor se suspende por inactividad.</p>
    {topology?.workers.map((worker) => <div className="worker" key={worker.worker_id}>
      <span className={`dot ${worker.state}`} aria-hidden="true" />
      <div><strong>{worker.pod_name}</strong><small className="worker-id">{worker.worker_id}</small>
        {worker.actor_id && <small className="worker-id">Actor: {worker.actor_id}</small>}</div>
      <span>{worker.state === 'busy' ? 'Ocupado' : worker.state === 'idle' ? 'Libre' : 'No disponible'}</span>
    </div>)}
    {topology && topology.workers.length === 0 && <p className="muted">Substrate no reportó workers del pool Codex.</p>}
    <h3>Actores</h3>
    {topology?.actors.map((actor) => <div className="actor-row" key={actor.actor_id}>
      <strong>{actor.actor_id}</strong><span>{actor.state}</span>
      {actor.worker_id && <small>Worker observado: {actor.worker_id}</small>}
    </div>)}
  </section>;
}

import type Database from 'better-sqlite3';
import type { FastifyInstance } from 'fastify';
import { setTimeout as delay } from 'node:timers/promises';
import { sendSse, startSse } from '../events/sse.js';
import { readTopology } from '../topology/service.js';
import { SubstrateError } from '../substrate/client.js';

export function registerTopology(app: FastifyInstance, db: Database.Database): void {
  app.get('/api/topology', async (_request, reply) => {
    try { return await readTopology(db); }
    catch (error) {
      if (error instanceof SubstrateError) return reply.code(503).send({ error: error.code });
      throw error;
    }
  });
  app.get('/api/topology/events', async (_request, reply) => {
    startSse(reply);
    let last = '';
    while (!reply.raw.destroyed) {
      try {
        const snapshot = await readTopology(db);
        const key = JSON.stringify({ actors: snapshot.actors.map(({ observed_at: _, ...actor }) => actor),
          workers: snapshot.workers.map(({ observed_at: _, ...worker }) => worker) });
        if (key !== last) { sendSse(reply, Date.now(), 'snapshot', snapshot); last = key; }
      } catch { reply.raw.write('event: unavailable\ndata: {}\n\n'); }
      await delay(2000);
    }
  });
}

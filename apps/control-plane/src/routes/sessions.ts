import { randomUUID } from 'node:crypto';
import type Database from 'better-sqlite3';
import type { FastifyInstance } from 'fastify';
import { mockActorId } from '../adapters/mock.js';
import { closeSession, createSession, readSession } from '../sessions/service.js';
import { SubstrateError } from '../substrate/client.js';

type Session = { id: string; actor_id: string; title: string; status: string; created_at: string; updated_at: string };

export function registerSessions(app: FastifyInstance, db: Database.Database): void {
  const real = process.env.POC_SUBSTRATE_MODE === 'real';
  app.get('/api/sessions', async () => db.prepare('SELECT * FROM sessions WHERE status != ? ORDER BY created_at DESC').all('closed'));
  app.post('/api/sessions', async (_request, reply) => {
    if (real) {
      try { return reply.code(201).send({ ...await createSession(db), source: 'substrate' }); }
      catch (error) {
        if (error instanceof SubstrateError) return reply.code(503).send({ error: error.code });
        throw error;
      }
    }
    const now = new Date().toISOString();
    const id = randomUUID();
    const session: Session = { id, actor_id: mockActorId(id), title: 'Nueva sesión', status: 'ready', created_at: now, updated_at: now };
    db.prepare('INSERT INTO sessions VALUES (@id, @actor_id, @title, @status, @created_at, @updated_at)').run(session);
    return reply.code(201).send({ ...session, source: 'mock' });
  });
  app.get<{ Params: { sessionId: string } }>('/api/sessions/:sessionId', async (request, reply) => {
    if (real) {
      try {
        const session = await readSession(db, request.params.sessionId);
        return session ? { ...session, source: 'substrate' } : reply.code(404).send({ error: 'not_found' });
      } catch (error) {
        if (error instanceof SubstrateError) return reply.code(503).send({ error: error.code });
        throw error;
      }
    }
    const session = db.prepare('SELECT * FROM sessions WHERE id = ? AND status != ?').get(request.params.sessionId, 'closed');
    return session ? { ...(session as object), source: 'mock' } : reply.code(404).send({ error: 'not_found' });
  });
  app.delete<{ Params: { sessionId: string } }>('/api/sessions/:sessionId', async (request, reply) => {
    if (real) {
      try { return await closeSession(db, request.params.sessionId) ? reply.code(204).send() : reply.code(404).send({ error: 'not_found' }); }
      catch (error) {
        if (error instanceof SubstrateError) return reply.code(503).send({ error: error.code });
        throw error;
      }
    }
    const result = db.prepare('UPDATE sessions SET status = ?, updated_at = ? WHERE id = ? AND status != ?')
      .run('closed', new Date().toISOString(), request.params.sessionId, 'closed');
    return result.changes ? reply.code(204).send() : reply.code(404).send({ error: 'not_found' });
  });
}

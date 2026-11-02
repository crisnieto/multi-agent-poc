import Fastify from 'fastify';
import { registerAuth } from './auth.js';
import { openDb } from './db/index.js';
import { mockTopology } from './adapters/mock.js';
import { registerSessions } from './routes/sessions.js';
import { registerRequests } from './routes/requests.js';
import { sendSse, startSse } from './events/sse.js';
import { registerTopology } from './routes/topology.js';
import { startIdleSuspender } from './sessions/idle-suspender.js';

const app = Fastify({ logger: { redact: ['req.headers.cookie', 'req.body.password', 'req.body.text'] } });
const db = openDb();
await registerAuth(app);
app.get('/api/healthz', async () => ({ status: 'ok', mode: process.env.POC_SUBSTRATE_MODE === 'real' ? 'substrate' : 'mock' }));
registerSessions(app, db);
registerRequests(app, db);
if (process.env.POC_SUBSTRATE_MODE === 'real') {
  registerTopology(app, db);
  const stopIdle = startIdleSuspender(db);
  app.addHook('onClose', async () => stopIdle());
}
else {
  app.get('/api/topology', async () => ({ ...mockTopology, observed_at: new Date().toISOString() }));
  app.get('/api/topology/events', async (_request, reply) => {
    startSse(reply);
    sendSse(reply, 1, 'snapshot', { ...mockTopology, observed_at: new Date().toISOString() });
    reply.raw.end();
  });
}
await app.listen({ host: process.env.POC_HOST ?? '127.0.0.1', port: Number(process.env.POC_PORT ?? 8080) });

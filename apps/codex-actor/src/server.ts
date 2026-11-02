import Fastify from 'fastify';
import { CodexClient, type TurnEvent } from './codex-client.js';

const app = Fastify({ logger: { redact: ['req.body', 'req.headers.authorization'] } });
let client: CodexClient | null = null;
const completed = new Map<string, TurnEvent[]>();
let busy = false;

function getClient(): CodexClient { return client ??= new CodexClient(); }
app.get('/healthz', async (_request, reply) => {
  try { await getClient().ready(); return { status: 'ok' }; }
  catch { return reply.code(503).send({ error: 'codex_unavailable' }); }
});
app.post<{ Body: { request_id?: unknown; text?: unknown } }>('/turns', async (request, reply) => {
  const id = request.body?.request_id;
  const text = request.body?.text;
  if (typeof id !== 'string' || typeof text !== 'string' || !text.trim() || text.length > 16000) {
    return reply.code(400).send({ error: 'invalid_request' });
  }
  if (busy && !completed.has(id)) return reply.code(409).send({ error: 'actor_busy' });
  reply.hijack();
  reply.raw.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache, no-transform' });
  const send = (event: TurnEvent) => reply.raw.write(`event: ${event.type}\ndata: ${JSON.stringify({ request_id: id, ...event })}\n\n`);
  if (completed.has(id)) { for (const event of completed.get(id)!) send(event); reply.raw.end(); return; }
  busy = true;
  const events: TurnEvent[] = [];
  const codex = getClient();
  const listener = (event: TurnEvent) => { events.push(event); send(event); };
  codex.on('event', listener);
  try {
    await codex.turn(text);
    completed.set(id, events);
  } catch {
    if (!events.some((event) => event.type === 'failed')) {
      const failed: TurnEvent = { type: 'failed', code: 'codex_turn_failed' };
      events.push(failed);
      send(failed);
    }
    completed.set(id, events);
  } finally {
    codex.off('event', listener);
    busy = false;
    reply.raw.end();
  }
});
await app.listen({ host: process.env.ACTOR_HOST ?? '127.0.0.1', port: Number(process.env.ACTOR_PORT ?? 8090) });
process.once('SIGTERM', () => {
  client?.close();
  void app.close();
});

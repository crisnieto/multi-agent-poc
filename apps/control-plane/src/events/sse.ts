import type { FastifyReply } from 'fastify';

export function startSse(reply: FastifyReply): void {
  reply.hijack();
  reply.raw.writeHead(200, {
    'content-type': 'text/event-stream; charset=utf-8',
    'cache-control': 'no-cache, no-transform',
    connection: 'keep-alive',
    'x-accel-buffering': 'no',
  });
}

export function sendSse(reply: FastifyReply, id: number, type: string, data: unknown): boolean {
  return reply.raw.write(`id: ${id}\nevent: ${type}\ndata: ${JSON.stringify(data)}\n\n`);
}

export async function waitForDrain(reply: FastifyReply): Promise<void> {
  if (reply.raw.destroyed) return;
  await new Promise<void>((resolve) => {
    const done = () => { reply.raw.off('drain', done); reply.raw.off('close', done); resolve(); };
    reply.raw.once('drain', done);
    reply.raw.once('close', done);
  });
}

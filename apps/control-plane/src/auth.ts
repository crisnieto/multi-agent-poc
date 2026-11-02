import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import cookie from '@fastify/cookie';

const password = process.env.POC_OPERATOR_PASSWORD;
const key = randomBytes(32);

function signature(value: string): string {
  return createHmac('sha256', key).update(value).digest('hex');
}

function authenticated(request: FastifyRequest): boolean {
  const value = request.cookies.poc_session;
  if (!value || !value.startsWith('operator.')) return false;
  const expected = `operator.${signature('operator')}`;
  return value.length === expected.length && timingSafeEqual(Buffer.from(value), Buffer.from(expected));
}

export async function registerAuth(app: FastifyInstance): Promise<void> {
  await app.register(cookie);
  app.post('/api/auth/login', async (request, reply) => {
    const supplied = (request.body as { password?: unknown } | undefined)?.password;
    if (!password || typeof supplied !== 'string' || supplied.length !== password.length ||
        !timingSafeEqual(Buffer.from(supplied), Buffer.from(password))) {
      return reply.code(401).send({ error: 'invalid_credentials' });
    }
    reply.setCookie('poc_session', `operator.${signature('operator')}`, {
      httpOnly: true, sameSite: 'strict', secure: process.env.POC_COOKIE_SECURE === 'true', path: '/api',
    });
    return reply.code(204).send();
  });
  app.addHook('onRequest', async (request: FastifyRequest, reply: FastifyReply) => {
    if (request.url === '/api/healthz' || request.url === '/api/auth/login') return;
    if (!authenticated(request)) return reply.code(401).send({ error: 'unauthorized' });
  });
}

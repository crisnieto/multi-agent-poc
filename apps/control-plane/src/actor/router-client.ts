import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { setTimeout as delay } from 'node:timers/promises';

const cli = process.env.POC_ATE_CLI ?? 'kubectl-ate';
const atespace = process.env.POC_ATESPACE ?? 'ate-demo-counter';

export type ActorTurnEvent = { type: 'started' | 'delta' | 'completed' | 'failed'; text?: string; code?: string };

async function freePort(): Promise<number> {
  const server = createServer();
  await new Promise<void>((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  const address = server.address();
  const port = typeof address === 'object' && address ? address.port : 0;
  await new Promise<void>((resolve) => server.close(() => resolve()));
  return port;
}

export async function streamActorTurn(actorId: string, requestId: string, text: string, onEvent: (event: ActorTurnEvent) => void): Promise<void> {
  if (!/^[a-z0-9-]+$/.test(actorId)) throw new Error('invalid_actor_id');
  const port = await freePort();
  // kubectl-ate owns the mTLS router connection and sets ate-target-actor from
  // this trusted actor ID. The browser cannot supply either value.
  const proxy = spawn(cli, ['proxy', 'actor', actorId, `${port}:8090`, '-a', atespace], { stdio: 'ignore' });
  let proxyError = false;
  proxy.on('error', () => { proxyError = true; });
  const abort = new AbortController();
  const timer = setTimeout(() => abort.abort(), 120_000);
  try {
    let ready = false;
    for (let attempt = 0; attempt < 60; attempt++) {
      if (proxyError || proxy.exitCode !== null) throw new Error('router_proxy_exited');
      try {
        const response = await fetch(`http://127.0.0.1:${port}/healthz`, { signal: AbortSignal.timeout(1000) });
        if (response.ok) { ready = true; break; }
      } catch { /* Proxy startup is asynchronous. */ }
      await delay(250);
    }
    if (!ready) throw new Error('router_unavailable');
    const response = await fetch(`http://127.0.0.1:${port}/turns`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ request_id: requestId, text }), signal: abort.signal,
    });
    if (!response.ok || !response.body) throw new Error(`actor_http_${response.status}`);
    let buffer = '';
    const decoder = new TextDecoder();
    for await (const chunk of response.body) {
      buffer += decoder.decode(chunk, { stream: true });
      let boundary: number;
      while ((boundary = buffer.indexOf('\n\n')) !== -1) {
        const frame = buffer.slice(0, boundary).replace(/\r/g, '');
        buffer = buffer.slice(boundary + 2);
        const data = frame.split('\n').find((line) => line.startsWith('data: '))?.slice(6);
        if (!data) continue;
        const event = JSON.parse(data) as ActorTurnEvent;
        if (['started', 'delta', 'completed', 'failed'].includes(event.type)) onEvent(event);
      }
    }
  } finally {
    clearTimeout(timer);
    proxy.kill('SIGTERM');
  }
}

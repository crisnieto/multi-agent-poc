import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import { EventEmitter } from 'node:events';
import { readFileSync, writeFileSync, existsSync, mkdirSync, copyFileSync } from 'node:fs';
import { resolve } from 'node:path';
import readline from 'node:readline';

type RpcMessage = { id?: number; method?: string; params?: Record<string, unknown>; result?: Record<string, unknown>; error?: { code?: number; message?: string } };
export type TurnEvent = { type: 'started' | 'delta' | 'completed' | 'failed'; text?: string; thread_id?: string; code?: string };

export class CodexClient extends EventEmitter {
  private process: ChildProcessWithoutNullStreams;
  private nextId = 1;
  private pending = new Map<number, { resolve: (v: Record<string, unknown>) => void; reject: (e: Error) => void }>();
  private threadId: string | null = null;
  private statePath = process.env.CODEX_THREAD_STATE_PATH ?? resolve(process.cwd(), 'codex-thread.json');
  private active: { resolve: () => void; reject: (error: Error) => void; text: string } | null = null;
  private lastFailureCode = 'codex_turn_failed';
  private readyPromise: Promise<void>;

  constructor() {
    super();
    const codexHome = process.env.CODEX_HOME ?? resolve(process.cwd(), '.codex');
    mkdirSync(codexHome, { recursive: true, mode: 0o700 });
    const configPath = resolve(codexHome, 'config.toml');
    if (!existsSync(configPath)) copyFileSync(resolve(import.meta.dirname, '../config/config.toml'), configPath);
    this.process = spawn(process.env.CODEX_BIN ?? 'codex', ['app-server'], {
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env, CODEX_HOME: codexHome },
    });
    this.process.stderr.resume(); // Do not log app-server stderr: it may contain sensitive data.
    this.process.on('error', (error) => this.fail(error));
    this.process.on('exit', () => this.fail(new Error('codex_app_server_exited')));
    readline.createInterface({ input: this.process.stdout }).on('line', (line) => this.receive(line));
    this.readyPromise = this.initialize();
  }

  private send(message: Record<string, unknown>): void {
    if (!this.process.stdin.writable) throw new Error('codex_app_server_unavailable');
    this.process.stdin.write(`${JSON.stringify(message)}\n`);
  }

  private rpc(method: string, params: Record<string, unknown>): Promise<Record<string, unknown>> {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.send({ id, method, params });
    });
  }

  private async initialize(): Promise<void> {
    await this.rpc('initialize', { clientInfo: { name: 'substrate_poc', title: 'Substrate PoC', version: '0.1.0' } });
    this.send({ method: 'initialized', params: {} });
    if (existsSync(this.statePath)) {
      const stored = JSON.parse(readFileSync(this.statePath, 'utf8')) as { thread_id?: string };
      if (stored.thread_id) {
        const result = await this.rpc('thread/resume', { threadId: stored.thread_id });
        this.threadId = (result.thread as { id?: string } | undefined)?.id ?? stored.thread_id;
      }
    }
  }

  private receive(line: string): void {
    let message: RpcMessage;
    try { message = JSON.parse(line) as RpcMessage; } catch { return; }
    if (typeof message.id === 'number') {
      const pending = this.pending.get(message.id);
      if (pending) {
        this.pending.delete(message.id);
        if (message.error) {
          if (process.env.POC_DEBUG_SAFE === 'true') {
            const key = process.env.OPENAI_API_KEY;
            const raw = message.error.message ?? 'codex_rpc_error';
            const withoutKey = key ? raw.split(key).join('[REDACTED]') : raw;
            const safe = withoutKey.replace(/sk-[A-Za-z0-9_-]+/g, '[REDACTED]').replace(/Bearer\s+\S+/gi, 'Bearer [REDACTED]').slice(0, 300);
            process.stderr.write(`codex_rpc_error ${message.error.code ?? 'unknown'}: ${safe}\n`);
          }
          pending.reject(new Error('codex_rpc_error'));
        }
        else pending.resolve(message.result ?? {});
      } else if (message.method) {
        // The PoC has no interactive approvals. Decline server-initiated requests.
        this.send({ id: message.id, result: { decision: 'decline' } });
      }
      return;
    }
    if (!this.active || !message.method) return;
    if (message.method === 'error') {
      const detail = JSON.stringify(message.params ?? {});
      const status = detail.match(/\b(401|403|404|429|500|502|503)\b/)?.[1];
      if (status) this.lastFailureCode = `provider_http_${status}`;
    }
    if (message.method === 'item/agentMessage/delta') {
      const delta = String(message.params?.delta ?? '');
      this.active.text += delta;
      this.emit('event', { type: 'delta', text: delta } satisfies TurnEvent);
    }
    if (message.method === 'turn/completed') {
      const turn = message.params?.turn as { status?: string } | undefined;
      if (turn?.status === 'completed') {
        this.emit('event', { type: 'completed', text: this.active.text } satisfies TurnEvent);
        this.active.resolve();
      } else {
        const detail = JSON.stringify(message.params?.turn ?? {});
        const status = detail.match(/\b(401|403|404|429|500|502|503)\b/)?.[1];
        this.emit('event', { type: 'failed', code: status ? `provider_http_${status}` : this.lastFailureCode } satisfies TurnEvent);
        this.active.reject(new Error('codex_turn_failed'));
      }
      this.active = null;
    }
  }

  private fail(error: Error): void {
    for (const pending of this.pending.values()) pending.reject(error);
    this.pending.clear();
    if (this.active) { this.active.reject(error); this.active = null; }
  }

  async ready(): Promise<void> { await this.readyPromise; }

  close(): void {
    this.process.kill('SIGTERM');
  }

  async turn(text: string): Promise<void> {
    await this.ready();
    if (this.active) throw new Error('actor_busy');
    if (!this.threadId) {
      const result = await this.rpc('thread/start', {
        model: 'gpt-6-luna',
        approvalPolicy: 'never',
        sandbox: 'read-only',
      });
      this.threadId = (result.thread as { id?: string } | undefined)?.id ?? null;
      if (!this.threadId) throw new Error('thread_start_failed');
      writeFileSync(this.statePath, JSON.stringify({ thread_id: this.threadId }), { mode: 0o600 });
    }
    const prompt = readFileSync(resolve(import.meta.dirname, '../config/system-prompt.md'), 'utf8');
    const input = this.nextId === 3 ? `${prompt}\n\n${text}` : text;
    let resolveTurn!: () => void;
    let rejectTurn!: (error: Error) => void;
    const done = new Promise<void>((resolve, reject) => { resolveTurn = resolve; rejectTurn = reject; });
    this.lastFailureCode = 'codex_turn_failed';
    this.active = { resolve: resolveTurn, reject: rejectTurn, text: '' };
    this.emit('event', { type: 'started', thread_id: this.threadId } satisfies TurnEvent);
    try {
      await this.rpc('turn/start', {
        threadId: this.threadId,
        model: 'gpt-6-luna',
        effort: 'none',
        input: [{ type: 'text', text: input }],
      });
      await done;
    } catch (error) {
      this.active = null;
      throw error;
    }
  }
}

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const atespace = process.env.POC_ATESPACE ?? 'ate-demo-counter';
const template = process.env.POC_ACTOR_TEMPLATE ?? 'codex-poc';
const cli = process.env.POC_ATE_CLI ?? 'kubectl-ate';
const actorName = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;

export type ActorRecord = {
  metadata?: { name?: string; uid?: string };
  status?: { state?: string; workerAssignment?: { worker?: { name?: string }; workerPod?: string } };
};
export type WorkerRecord = {
  metadata?: { name?: string };
  workerPod?: string;
  workerPool?: string;
  status?: { state?: string; allocated?: { actors?: number } };
};

export class SubstrateError extends Error {
  constructor(public readonly code: 'invalid_actor_id' | 'actor_not_found' | 'substrate_unavailable', public readonly actorId?: string) {
    super(code);
  }
}

async function run(args: string[], actorId?: string): Promise<string> {
  try {
    const result = await execFileAsync(cli, args, { timeout: 30_000, maxBuffer: 2 * 1024 * 1024 });
    return result.stdout;
  } catch (error) {
    const stderr = String((error as { stderr?: unknown }).stderr ?? '');
    throw new SubstrateError(/not found|does not exist/i.test(stderr) ? 'actor_not_found' : 'substrate_unavailable', actorId);
  }
}

function assertName(id: string): void {
  if (!actorName.test(id)) throw new SubstrateError('invalid_actor_id', id);
}

export async function createActor(id: string): Promise<void> {
  assertName(id);
  await run(['create', 'actor', id, '-a', atespace, '--template', template], id);
}

export async function getActor(id: string): Promise<ActorRecord> {
  assertName(id);
  const output = await run(['get', 'actor', id, '-a', atespace, '-o', 'json'], id);
  try { return JSON.parse(output) as ActorRecord; }
  catch { throw new SubstrateError('substrate_unavailable', id); }
}

export async function suspendActor(id: string): Promise<void> {
  assertName(id);
  await run(['suspend', 'actor', id, '-a', atespace, '--mode=sync'], id);
}

export async function deleteActor(id: string): Promise<void> {
  assertName(id);
  await run(['delete', 'actor', id, '-a', atespace], id);
}

export async function configureActorEgress(id: string, policyPath: string): Promise<void> {
  assertName(id);
  await run(['create', 'egress-policy', id, '-a', atespace, '-f', policyPath], id);
}

export async function listActors(): Promise<ActorRecord[]> {
  const output = await run(['get', 'actors', '-a', atespace, '-o', 'json']);
  try { return (JSON.parse(output) as { actors?: ActorRecord[] }).actors ?? []; }
  catch { throw new SubstrateError('substrate_unavailable'); }
}

export async function listWorkers(): Promise<WorkerRecord[]> {
  const output = await run(['get', 'workers', '-n', atespace, '-o', 'json']);
  try { return (JSON.parse(output) as { workers?: WorkerRecord[] }).workers ?? []; }
  catch { throw new SubstrateError('substrate_unavailable'); }
}

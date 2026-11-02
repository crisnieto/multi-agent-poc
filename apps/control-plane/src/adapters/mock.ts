export function mockActorId(sessionId: string): string {
  return `mock-${sessionId}`;
}

export function mockAnswer(text: string): string {
  return `Respuesta simulada para: ${text}`;
}

export const mockTopology = {
  observed_at: new Date().toISOString(),
  source: 'mock',
  actors: [],
  workers: [
    { worker_id: 'mock-worker-1', pod_name: 'mock-pod-1', state: 'idle', observed_at: new Date().toISOString() },
    { worker_id: 'mock-worker-2', pod_name: 'mock-pod-2', state: 'idle', observed_at: new Date().toISOString() },
  ],
};

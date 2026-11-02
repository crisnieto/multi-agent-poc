export type Session = { id: string; actor_id: string; title: string; status: string; source: string };
export type ChatRequest = { id: string; session_id: string; status: string; final_text?: string | null; error_code?: string | null };
export type Actor = { actor_id: string; session_id: string; state: string; worker_id?: string; observed_at: string; source: string };
export type Worker = { worker_id: string; pod_name: string; state: string; actor_id?: string; observed_at: string; source: string };
export type Topology = { observed_at: string; source: string; actors: Actor[]; workers: Worker[] };

async function json<T>(path: string, options?: RequestInit): Promise<T> {
  const response = await fetch(`/api${path}`, { credentials: 'same-origin', ...options });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json() as Promise<T>;
}

export async function login(password: string): Promise<void> {
  const response = await fetch('/api/auth/login', { method: 'POST', credentials: 'same-origin',
    headers: { 'content-type': 'application/json' }, body: JSON.stringify({ password }) });
  if (!response.ok) throw new Error('Contraseña incorrecta o API no disponible');
}

export const listSessions = () => json<Session[]>('/sessions');
export const createSession = () => json<Session>('/sessions', { method: 'POST' });
export const deleteSession = async (id: string) => {
  const response = await fetch(`/api/sessions/${encodeURIComponent(id)}`, { method: 'DELETE', credentials: 'same-origin' });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
};
export const sendTurn = (id: string, text: string) => json<ChatRequest>(`/sessions/${encodeURIComponent(id)}/requests`, {
  method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ text }),
});
export const getRequest = (id: string) => json<ChatRequest>(`/requests/${encodeURIComponent(id)}`);
export const getTopology = () => json<Topology>('/topology');

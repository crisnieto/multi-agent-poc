export type RequestStatus = 'queued' | 'running' | 'completed' | 'failed' | 'timed_out' | 'cancelled';
export type RequestRow = {
  id: string; session_id: string; text: string; status: RequestStatus;
  final_text: string | null; error_code: string | null; created_at: string; updated_at: string;
};

const transitions: Record<RequestStatus, RequestStatus[]> = {
  queued: ['running', 'failed', 'timed_out', 'cancelled'],
  running: ['completed', 'failed', 'timed_out', 'cancelled'],
  completed: [], failed: [], timed_out: [], cancelled: [],
};

export function terminal(status: string): boolean { return ['completed', 'failed', 'timed_out', 'cancelled'].includes(status); }
export function canTransition(from: RequestStatus, to: RequestStatus): boolean { return transitions[from]?.includes(to) ?? false; }

import { useCallback, useEffect, useRef } from 'react';
import { getRequest } from '../api/client';

type Callbacks = {
  started: () => void;
  delta: (text: string) => void;
  completed: (text?: string | null) => void;
  failed: (code: string) => void;
  reconnecting: () => void;
};

export function useRequestEvents() {
  const streams = useRef(new Set<EventSource>());
  useEffect(() => () => { for (const stream of streams.current) stream.close(); streams.current.clear(); }, []);
  return useCallback((requestId: string, callbacks: Callbacks) => {
    const stream = new EventSource(`/api/requests/${encodeURIComponent(requestId)}/events`);
    streams.current.add(stream);
    let finished = false;
    const close = () => { if (finished) return false; finished = true; stream.close(); streams.current.delete(stream); return true; };
    stream.addEventListener('started', () => { if (!finished) callbacks.started(); });
    stream.addEventListener('delta', (item) => {
      if (finished) return;
      const data = JSON.parse((item as MessageEvent).data) as { text?: string };
      callbacks.delta(data.text ?? '');
    });
    stream.addEventListener('completed', (item) => {
      const data = JSON.parse((item as MessageEvent).data) as { text?: string };
      if (close()) callbacks.completed(data.text);
    });
    stream.addEventListener('failed', (item) => {
      const data = JSON.parse((item as MessageEvent).data) as { code?: string };
      if (close()) callbacks.failed(data.code ?? 'codex_turn_failed');
    });
    stream.onerror = async () => {
      if (finished) return;
      callbacks.reconnecting();
      try {
        const result = await getRequest(requestId);
        if (result.status === 'completed' && close()) callbacks.completed(result.final_text);
        else if (['failed', 'timed_out', 'cancelled'].includes(result.status) && close()) callbacks.failed(result.error_code ?? result.status);
      } catch { /* EventSource keeps retrying with Last-Event-ID. */ }
    };
    return close;
  }, []);
}

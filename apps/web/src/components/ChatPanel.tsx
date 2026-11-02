import type { FormEvent } from 'react';
import type { Session } from '../api/client';

export type Message = { role: 'user' | 'agent'; text: string; status?: string };

export function ChatPanel({ session, messages, text, busy, setText, onSubmit }: {
  session?: Session; messages: Message[]; text: string; busy: boolean;
  setText: (value: string) => void; onSubmit: (event: FormEvent) => void;
}) {
  return <section className="panel chat-panel"><h2>{session ? session.title : 'Elegí o creá una sesión'}</h2>
    {session && <p className="muted">Actor: {session.actor_id} · Estado: {session.status}</p>}
    <div className="messages">{messages.map((message, index) => <div className={`message ${message.role}`} key={index}>
      <b>{message.role === 'user' ? 'Tú' : 'Codex'}</b><p>{message.text || message.status}</p>
      {message.text && message.status && <small>{message.status}</small>}
    </div>)}</div>
    <form onSubmit={onSubmit}><input aria-label="Mensaje" value={text} onChange={(event) => setText(event.target.value)}
      disabled={!session || busy} placeholder="Escribe un mensaje" /><button disabled={!session || busy}>Enviar</button></form>
  </section>;
}

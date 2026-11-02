import { useEffect, useRef, useState, type FormEvent } from 'react';
import { createSession, deleteSession, getSessionMessages, getTopology, listSessions, login, sendTurn,
  type Session, type Topology } from '../api/client';
import { TopologyPanel } from '../components/TopologyPanel';
import { Timeline, type TimelineEntry } from '../components/Timeline';
import { ChatPanel, type Message } from '../components/ChatPanel';
import { useRequestEvents } from '../hooks/useRequestEvents';

export function Dashboard() {
  const [password, setPassword] = useState('');
  const [loggedIn, setLoggedIn] = useState(false);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [messages, setMessages] = useState<Record<string, Message[]>>({});
  const [text, setText] = useState('');
  const [topology, setTopology] = useState<Topology | null>(null);
  const [timeline, setTimeline] = useState<TimelineEntry[]>([]);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState('');
  const lastTopology = useRef<Topology | null>(null);
  const startEvents = useRequestEvents();

  useEffect(() => {
    if (!loggedIn) return;
    let cancelled = false;
    const refresh = async () => {
      try {
        const [nextSessions, nextTopology] = await Promise.all([listSessions(), getTopology()]);
        if (cancelled) return;
        setSessions(nextSessions);
        setTopology(nextTopology);
        const previous = lastTopology.current;
        if (previous) {
          const entries: TimelineEntry[] = [];
          for (const actor of nextTopology.actors) {
            const before = previous.actors.find((item) => item.actor_id === actor.actor_id);
            if (!before || before.state !== actor.state || before.worker_id !== actor.worker_id) {
              entries.push({ id: `${actor.actor_id}-${Date.now()}`, at: nextTopology.observed_at,
                message: `${actor.actor_id}: ${actor.state}${actor.worker_id ? ` en ${actor.worker_id}` : ''}` });
            }
          }
          if (entries.length) setTimeline((old) => [...entries, ...old].slice(0, 30));
        }
        lastTopology.current = nextTopology;
      } catch (cause) { if (!cancelled) setError(String(cause)); }
    };
    void refresh();
    const timer = setInterval(() => void refresh(), 2000);
    return () => { cancelled = true; clearInterval(timer); };
  }, [loggedIn]);

  useEffect(() => {
    if (!loggedIn || !selected || busy === selected) return;
    const sessionId = selected;
    let cancelled = false;
    const refreshMessages = async () => {
      try {
        const turns = await getSessionMessages(sessionId);
        if (cancelled) return;
        const restored: Message[] = turns.flatMap((turn) => [
          { role: 'user' as const, text: turn.text },
          { role: 'agent' as const, text: turn.final_text ?? '',
            ...(turn.status === 'completed' ? {} : { status: turn.status === 'failed'
              ? `Error: ${turn.error_code ?? 'codex_turn_failed'}`
              : turn.status === 'running' ? 'Trabajando' : 'Esperando' }) },
        ]);
        setMessages((old) => ({ ...old, [sessionId]: restored }));
      } catch (cause) { if (!cancelled) setError(String(cause)); }
    };
    void refreshMessages();
    const timer = setInterval(() => void refreshMessages(), 2000);
    return () => { cancelled = true; clearInterval(timer); };
  }, [loggedIn, selected, busy]);

  async function signIn(event: FormEvent) {
    event.preventDefault();
    try { await login(password); setPassword(''); setLoggedIn(true); setError(''); }
    catch (cause) { setError(String(cause)); }
  }

  async function addSession() {
    try { const session = await createSession(); setSessions((old) => [session, ...old]); setSelected(session.id); setError(''); }
    catch (cause) { setError(String(cause)); }
  }

  async function removeSession(id: string) {
    try { await deleteSession(id); setSessions((old) => old.filter((session) => session.id !== id));
      if (selected === id) setSelected(null); setError(''); }
    catch (cause) { setError(String(cause)); }
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!selected || busy || !text.trim()) return;
    const sessionId = selected;
    const value = text.trim();
    setText('');
    setBusy(sessionId);
    setMessages((old) => ({ ...old, [sessionId]: [...(old[sessionId] ?? []), { role: 'user', text: value }, { role: 'agent', text: '', status: 'Esperando' }] }));
    try {
      const request = await sendTurn(sessionId, value);
      const updateLast = (change: (message: Message) => Message) => setMessages((old) => {
        const list = [...(old[sessionId] ?? [])];
        if (list.length) list[list.length - 1] = change(list[list.length - 1]!);
        return { ...old, [sessionId]: list };
      });
      startEvents(request.id, {
        started: () => updateLast((message) => ({ ...message, status: 'Trabajando' })),
        delta: (delta) => updateLast((message) => ({ ...message, text: message.text + delta, status: 'Trabajando' })),
        completed: (answer) => { updateLast((message) => ({ ...message, text: answer ?? message.text, status: undefined })); setBusy(null); },
        failed: (code) => { updateLast((message) => ({ ...message, status: `Error: ${code}` })); setBusy(null); },
        reconnecting: () => updateLast((message) => ({ ...message, status: 'Reconectando' })),
      });
    } catch (cause) { setBusy(null); setError(String(cause)); }
  }

  if (!loggedIn) return <main><header><div><small>AGENT SUBSTRATE / POC</small><h1>Chat y multiplexación</h1></div><span className="badge">SUBSTRATE REAL</span></header>
    <section className="panel login-panel"><h2>Ingresar como operador</h2><form onSubmit={signIn}>
      <input type="password" aria-label="Contraseña" value={password} onChange={(event) => setPassword(event.target.value)} />
      <button>Ingresar</button></form>{error && <p role="alert">{error}</p>}</section></main>;

  const current = sessions.find((session) => session.id === selected);
  return <main><header><div><small>AGENT SUBSTRATE / POC</small><h1>Chat y multiplexación</h1></div><span className="badge">SUBSTRATE REAL</span></header>
    {error && <p role="alert" className="error">{error}</p>}
    <div className="dashboard-layout">
      <aside className="panel session-list"><h2>Sesiones</h2><button onClick={() => void addSession()}>Nuevo chat</button>
        {sessions.map((session) => <div className={`session-item ${selected === session.id ? 'selected' : ''}`} key={session.id}>
          <button className="session-select" onClick={() => setSelected(session.id)}>{session.title}<small>{session.actor_id}</small></button>
          <button className="remove" aria-label={`Cerrar ${session.id}`} onClick={() => void removeSession(session.id)}>×</button>
        </div>)}
      </aside>
      <ChatPanel session={current} messages={selected ? messages[selected] ?? [] : []} text={text} busy={!!busy}
        setText={setText} onSubmit={submit} />
      <div className="right-column"><TopologyPanel topology={topology} /><Timeline entries={timeline} /></div>
    </div>
  </main>;
}

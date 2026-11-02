import { useState } from 'react';

type Message = { role: 'user' | 'agent'; text: string };
const workers = [{ id: 'mock-pod-1', status: 'Libre' }, { id: 'mock-pod-2', status: 'Libre' }];

export function LocalDemo() {
  const [messages, setMessages] = useState<Message[]>([{ role: 'agent', text: 'Esta vista demuestra el frontend sin API. La topología es simulada.' }]);
  const [text, setText] = useState('');
  function send() {
    const value = text.trim();
    if (!value) return;
    setMessages((current) => [...current, { role: 'user', text: value }, { role: 'agent', text: `Respuesta simulada para: ${value}` }]);
    setText('');
  }
  return <main>
    <header><div><small>AGENT SUBSTRATE / POC LOCAL</small><h1>Chat y multiplexación</h1></div><span className="badge">DATOS SIMULADOS</span></header>
    <div className="grid">
      <section className="panel"><h2>Sesión de ejemplo</h2><p className="muted">Agente mock-demo · Sin conexión a Substrate</p>
        <div className="messages">{messages.map((m, i) => <div className={`message ${m.role}`} key={i}><b>{m.role === 'user' ? 'Tú' : 'Agente simulado'}</b><p>{m.text}</p></div>)}</div>
        <form onSubmit={(event) => { event.preventDefault(); send(); }}><input aria-label="Mensaje" value={text} onChange={(event) => setText(event.target.value)} placeholder="Escribe un mensaje" /><button>Enviar</button></form>
      </section>
      <section className="panel"><h2>Pods de trabajo</h2><p className="muted">Topología simulada para verificar el componente visual</p>
        {workers.map((w) => <div className="worker" key={w.id}><span className="dot"/><strong>{w.id}</strong><span>{w.status}</span></div>)}
        <h3>Actividad</h3><p className="muted">La línea de tiempo real se habilita durante la integración local.</p>
      </section>
    </div>
  </main>;
}

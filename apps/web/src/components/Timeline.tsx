export type TimelineEntry = { id: string; at: string; message: string };

export function Timeline({ entries }: { entries: TimelineEntry[] }) {
  return <section className="panel timeline-panel"><h2>Actividad observada</h2>
    {entries.length === 0 && <p className="muted">Los cambios de estado aparecerán aquí.</p>}
    {entries.map((entry) => <div className="timeline-entry" key={entry.id}>
      <time>{new Date(entry.at).toLocaleTimeString()}</time><span>{entry.message}</span>
    </div>)}
  </section>;
}

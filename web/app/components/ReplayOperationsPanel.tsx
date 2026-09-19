import type { DeadLetterEvent, ReplayAudit } from "../types";

type Props = { events: DeadLetterEvent[]; audits: ReplayAudit[]; busyId?: string; onReplay: (id: string) => void };

export default function ReplayOperationsPanel({ events, audits, busyId, onReplay }: Props) {
  const pending = events.filter((event) => event.status === "PENDING");
  return <section className="replayBoard">
    <div className="replayHeader"><div><p className="eyebrow">RECOVERY / DEAD LETTER QUEUE</p><h2>Selective event replay</h2></div><div><b>{pending.length}</b><span>PENDING</span></div></div>
    <div className="replayColumns">
      <div className="deadLetters"><h4>QUARANTINED EVENTS</h4>
        {events.length === 0 ? <p className="replayEmpty">격리된 telemetry 이벤트가 없습니다.</p> : events.slice(0, 8).map((event) => <div className="deadLetterRow" key={event.id}>
          <span className={`replayState ${event.status.toLowerCase()}`}>{event.status}</span>
          <span><b>{event.originalTopic}</b><small>{event.traceId || event.messageKey || event.id.slice(0, 8)} · p{event.dlqPartition}/o{event.dlqOffset}</small><em>{event.exceptionMessage || "Consumer processing failed"}</em></span>
          <button disabled={event.status !== "PENDING" || busyId === event.id} onClick={() => onReplay(event.id)}>{busyId === event.id ? "SENDING…" : "REPLAY"}</button>
        </div>)}
      </div>
      <div className="auditPane"><h4>REPLAY AUDIT</h4>
        {audits.length === 0 ? <p className="replayEmpty">Replay actions will be recorded here.</p> : audits.slice(0, 8).map((audit) => <div className="auditRow" key={audit.id}><span>↻</span><span><b>{audit.actor}</b><small>{audit.deadLetterEventId.slice(0, 8)} · {new Date(audit.occurredAt).toLocaleString("ko-KR")}</small></span></div>)}
      </div>
    </div>
  </section>;
}


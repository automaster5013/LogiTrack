import type { OutboxFailure, OutboxRetryAudit } from "../types";

type Props = { failures:OutboxFailure[]; audits:OutboxRetryAudit[]; busyId?:string; onRetry:(id:string)=>void };

export default function OutboxRecoveryPanel({failures,audits,busyId,onRetry}:Props){
  return <section className="replayBoard">
    <div className="replayHeader"><div><p className="eyebrow">RECOVERY / TRANSACTIONAL OUTBOX</p><h2>Failed event recovery</h2></div><div><b>{failures.length}</b><span>FAILED</span></div></div>
    <div className="replayColumns">
      <div className="deadLetters"><h4>FAILED PUBLICATIONS</h4>
        {failures.length===0?<p className="replayEmpty">발행에 실패한 outbox 이벤트가 없습니다.</p>:failures.slice(0,8).map(event=><div className="deadLetterRow" key={event.id}>
          <span className="replayState pending">FAILED ×{event.attempts}</span>
          <span><b>{event.eventType}</b><small>{event.aggregateType} · {event.aggregateId.slice(0,8)} · {event.topic}</small><em>{event.lastError||"Publishing failed"}</em></span>
          <button disabled={busyId===event.id} onClick={()=>onRetry(event.id)}>{busyId===event.id?"QUEUING…":"RETRY"}</button>
        </div>)}
      </div>
      <div className="auditPane"><h4>RETRY AUDIT</h4>
        {audits.length===0?<p className="replayEmpty">Outbox retry actions will be recorded here.</p>:audits.slice(0,8).map(audit=><div className="auditRow" key={audit.id}><span>↻</span><span><b>{audit.actor}</b><small>{audit.outboxEventId.slice(0,8)} · {new Date(audit.occurredAt).toLocaleString("ko-KR")}</small></span></div>)}
      </div>
    </div>
  </section>;
}

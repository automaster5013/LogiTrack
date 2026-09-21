import { useEffect, useState } from "react";
import type { OutboxFailure, OutboxRetryAudit } from "../types";

type Props = { failures:OutboxFailure[]; audits:OutboxRetryAudit[]; busyId?:string; onRetry:(id:string)=>void };

export default function OutboxRecoveryPanel({failures,audits,busyId,onRetry}:Props){
  const [visibleFailures,setVisibleFailures]=useState(8);
  const [visibleAudits,setVisibleAudits]=useState(8);
  useEffect(()=>setVisibleFailures(current=>Math.min(Math.max(current,8),Math.max(failures.length,8))),[failures.length]);
  useEffect(()=>setVisibleAudits(current=>Math.min(Math.max(current,8),Math.max(audits.length,8))),[audits.length]);
  const shownFailures=failures.slice(0,visibleFailures);
  const shownAudits=audits.slice(0,visibleAudits);
  return <section className="replayBoard">
    <div className="replayHeader"><div><p className="eyebrow">복구 / 이벤트 발행함</p><h2>발행 실패 복구</h2></div><div><b>{failures.length}</b><span>발행 실패</span></div></div>
    <div className="replayColumns">
      <div className="deadLetters"><h4>발행 실패 이벤트</h4>
        {failures.length===0?<p className="replayEmpty">발행에 실패한 outbox 이벤트가 없습니다.</p>:shownFailures.map(event=><div className="deadLetterRow" key={event.id}>
          <span className="replayState pending">실패 {event.attempts}회</span>
          <span><b>{event.eventType}</b><small>{event.aggregateType} · {event.aggregateId.slice(0,8)} · {event.topic}</small><em>{event.lastError||"이벤트 발행에 실패했습니다."}</em></span>
          <button disabled={busyId===event.id} onClick={()=>onRetry(event.id)} aria-label={`${event.eventType} 재발행`}>{busyId===event.id?"대기열 등록 중…":"다시 발행"}</button>
        </div>)}
        {failures.length>8&&<RecoveryListFooter label="실패 이벤트" shown={shownFailures.length} total={failures.length} step={8} onChange={setVisibleFailures}/>}
      </div>
      <div className="auditPane"><h4>재발행 작업 이력</h4>
        {audits.length===0?<p className="replayEmpty">이벤트 재발행 작업이 여기에 기록됩니다.</p>:shownAudits.map(audit=><div className="auditRow" key={audit.id}><span>↻</span><span><b>{audit.actor}</b><small>{audit.outboxEventId.slice(0,8)} · {new Date(audit.occurredAt).toLocaleString("ko-KR")}</small></span></div>)}
        {audits.length>8&&<RecoveryListFooter label="작업 이력" shown={shownAudits.length} total={audits.length} step={8} onChange={setVisibleAudits}/>}
      </div>
    </div>
  </section>;
}

function RecoveryListFooter({label,shown,total,step,onChange}:{label:string;shown:number;total:number;step:number;onChange:(value:number)=>void}){
  const remaining=total-shown;
  return <div className="recoveryListFooter"><span aria-live="polite">{label} {shown} / {total}건 표시</span>{remaining>0?<button type="button" onClick={()=>onChange(Math.min(shown+step,total))}>다음 {Math.min(step,remaining)}건 보기</button>:<button type="button" onClick={()=>onChange(step)}>최근 {step}건만 보기</button>}</div>;
}

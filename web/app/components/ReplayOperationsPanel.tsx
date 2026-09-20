import { FormEvent, useEffect, useState } from "react";
import type { DeadLetterEvent, DiscardPlan, ReplayAudit } from "../types";

type Props = { events: DeadLetterEvent[]; audits: ReplayAudit[]; busyId?: string; discardPlan?: DiscardPlan; discardPlanBusy: boolean; onReplay: (id: string) => void; onDiscard: (id: string) => void; onPrepareDiscard: (ids:string[],reason:string) => void; onExecuteDiscard: (id:string) => void; onResetDiscardPlan: () => void };

export default function ReplayOperationsPanel({ events, audits, busyId, discardPlan, discardPlanBusy, onReplay, onDiscard, onPrepareDiscard, onExecuteDiscard, onResetDiscardPlan }: Props) {
  const pending = events.filter((event) => event.status === "PENDING");
  const [selectedIds,setSelectedIds]=useState<string[]>([]);
  const [reason,setReason]=useState("");
  const [approval,setApproval]=useState("");
  useEffect(()=>setSelectedIds(current=>current.filter(id=>events.some(event=>event.id===id&&event.status==="PENDING"))),[events]);
  const toggle=(id:string)=>setSelectedIds(current=>current.includes(id)?current.filter(value=>value!==id):current.length<20?[...current,id]:current);
  const prepare=(event:FormEvent)=>{event.preventDefault();onPrepareDiscard(selectedIds,reason)};
  const reset=()=>{setSelectedIds([]);setReason("");setApproval("");onResetDiscardPlan()};
  return <section className="replayBoard">
    <div className="replayHeader"><div><p className="eyebrow">RECOVERY / DEAD LETTER QUEUE</p><h2>Selective event disposition</h2></div><div><b>{pending.length}</b><span>PENDING</span></div></div>
    <div className="replayColumns">
      <div className="deadLetters"><h4>QUARANTINED EVENTS</h4>
        {events.length === 0 ? <p className="replayEmpty">격리된 telemetry 이벤트가 없습니다.</p> : events.slice(0, 20).map((event) => <div className={`deadLetterRow ${selectedIds.includes(event.id)?"selected":""}`} key={event.id}>
          <input className="discardSelect" type="checkbox" aria-label={`${event.traceId||event.id} 일괄 폐기 선택`} checked={selectedIds.includes(event.id)} disabled={Boolean(discardPlan)||(!selectedIds.includes(event.id)&&selectedIds.length>=20)} onChange={()=>toggle(event.id)}/>
          <span className={`replayState ${event.status.toLowerCase()}`}>{event.status}</span>
          <span><b>{event.originalTopic}</b><small>{event.traceId || event.messageKey || event.id.slice(0, 8)} · p{event.dlqPartition}/o{event.dlqOffset}</small><em>{event.exceptionMessage || "Consumer processing failed"}</em></span>
          <span className="replayActions"><button disabled={event.status !== "PENDING" || busyId === event.id} onClick={() => onReplay(event.id)}>{busyId === event.id ? "WORKING…" : "REPLAY"}</button><button className="discard" disabled={event.status !== "PENDING" || busyId === event.id} onClick={() => onDiscard(event.id)}>DISCARD</button></span>
        </div>)}
        <form className="discardPlan" onSubmit={prepare}>
          {!discardPlan&&<><label><span>BATCH REASON</span><input value={reason} maxLength={500} onChange={event=>setReason(event.target.value)} placeholder="폐기 사유를 입력하세요"/></label><button disabled={discardPlanBusy||selectedIds.length===0||!reason.trim()}>{discardPlanBusy?"PREPARING…":`REVIEW ${selectedIds.length} EVENT${selectedIds.length===1?"":"S"}`}</button><small>최대 20건 · 계획 생성 후 10분 이내 별도 승인이 필요합니다.</small></>}
          {discardPlan&&<div className={`discardReview ${discardPlan.status.toLowerCase()}`}><div><b>{discardPlan.status} · {discardPlan.eventIds.length} EVENTS</b><small>{discardPlan.reason}</small><small>만료 {new Date(discardPlan.expiresAt).toLocaleString("ko-KR")}</small></div>{discardPlan.status==="PREPARED"?<><label><span>TYPE DISCARD</span><input value={approval} onChange={event=>setApproval(event.target.value)} autoComplete="off"/></label><span className="discardApprovalActions"><button type="button" className="discard" disabled={discardPlanBusy||approval!=="DISCARD"} onClick={()=>onExecuteDiscard(discardPlan.id)}>{discardPlanBusy?"DISCARDING…":"EXECUTE DISCARD"}</button><button type="button" disabled={discardPlanBusy} onClick={reset}>CANCEL</button></span></>:<><strong>{discardPlan.succeededCount} succeeded · {discardPlan.failedCount} failed</strong><button type="button" onClick={reset}>NEW PLAN</button></>}</div>}
        </form>
      </div>
      <div className="auditPane"><h4>RECOVERY AUDIT</h4>
        {audits.length === 0 ? <p className="replayEmpty">Recovery actions will be recorded here.</p> : audits.slice(0, 8).map((audit) => <div className="auditRow" key={audit.id}><span>{audit.action === "DISCARD" ? "×" : "↻"}</span><span><b>{audit.action} · {audit.actor}</b><small>{audit.deadLetterEventId.slice(0, 8)} · {new Date(audit.occurredAt).toLocaleString("ko-KR")}</small>{audit.reason&&<small>{audit.reason}</small>}</span></div>)}
      </div>
    </div>
  </section>;
}

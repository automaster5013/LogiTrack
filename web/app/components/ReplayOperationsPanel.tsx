import { FormEvent, useEffect, useState } from "react";
import type { DeadLetterEvent, DiscardPlan, ReplayAudit } from "../types";

type Props = { events: DeadLetterEvent[]; totalEvents:number; audits: ReplayAudit[]; busyId?: string; pageBusy:boolean; discardPlan?: DiscardPlan; discardPlanBusy: boolean; onReplay: (id: string) => void; onDiscard: (id: string) => void; onLoadMore:()=>void; onPrepareDiscard: (ids:string[],reason:string) => void; onExecuteDiscard: (id:string) => void; onResetDiscardPlan: () => void };

const eventStatusLabel: Record<DeadLetterEvent["status"],string> = {PENDING:"복구 대기",REPLAYED:"재처리 완료",DISCARDED:"폐기 완료"};
const auditActionLabel: Record<ReplayAudit["action"],string> = {REPLAY:"재처리",DISCARD:"폐기"};
const planStatusLabel: Record<DiscardPlan["status"],string> = {PREPARED:"승인 대기",EXECUTED:"실행 완료",PARTIAL:"일부 완료",EXPIRED:"만료됨"};

export default function ReplayOperationsPanel({ events, totalEvents, audits, busyId, pageBusy, discardPlan, discardPlanBusy, onReplay, onDiscard, onLoadMore, onPrepareDiscard, onExecuteDiscard, onResetDiscardPlan }: Props) {
  const pending = events.filter((event) => event.status === "PENDING");
  const [selectedIds,setSelectedIds]=useState<string[]>([]);
  const [reason,setReason]=useState("");
  const [approval,setApproval]=useState("");
  useEffect(()=>setSelectedIds(current=>current.filter(id=>events.some(event=>event.id===id&&event.status==="PENDING"))),[events]);
  const toggle=(id:string)=>setSelectedIds(current=>current.includes(id)?current.filter(value=>value!==id):current.length<20?[...current,id]:current);
  const prepare=(event:FormEvent)=>{event.preventDefault();onPrepareDiscard(selectedIds,reason)};
  const reset=()=>{setSelectedIds([]);setReason("");setApproval("");onResetDiscardPlan()};
  return <section className="replayBoard">
    <div className="replayHeader"><div><p className="eyebrow">복구 / 격리 이벤트</p><h2>실패 이벤트 검토</h2></div><div><b>{totalEvents}</b><span>복구 대기 · {pending.length}건 불러옴</span></div></div>
    <div className="replayColumns">
      <div className="deadLetters"><h4>격리된 이벤트</h4>
        {events.length === 0 ? <p className="replayEmpty">격리된 telemetry 이벤트가 없습니다.</p> : events.map((event) => <div className={`deadLetterRow ${selectedIds.includes(event.id)?"selected":""}`} key={event.id}>
          <input className="discardSelect" type="checkbox" aria-label={`${event.traceId||event.id} 일괄 폐기 선택`} checked={selectedIds.includes(event.id)} disabled={Boolean(discardPlan)||(!selectedIds.includes(event.id)&&selectedIds.length>=20)} onChange={()=>toggle(event.id)}/>
          <span className={`replayState ${event.status.toLowerCase()}`}>{eventStatusLabel[event.status]}</span>
          <span><b>{event.originalTopic}</b><small>{event.traceId || event.messageKey || event.id.slice(0, 8)} · 파티션 {event.dlqPartition} / 오프셋 {event.dlqOffset}</small><em>{event.exceptionMessage || "이벤트 처리에 실패했습니다."}</em></span>
          <span className="replayActions"><button disabled={event.status !== "PENDING" || busyId === event.id} onClick={() => onReplay(event.id)} aria-label={`${event.traceId||event.id} 재처리`}>{busyId === event.id ? "처리 중…" : "재처리"}</button><button className="discard" disabled={event.status !== "PENDING" || busyId === event.id} onClick={() => onDiscard(event.id)} aria-label={`${event.traceId||event.id} 영구 폐기`}>영구 폐기</button></span>
        </div>)}
        {events.length<totalEvents&&<button className="loadMoreDlq" disabled={pageBusy} onClick={onLoadMore}>{pageBusy?"불러오는 중…":`이전 이벤트 ${Math.min(100,totalEvents-events.length)}건 더 보기`}</button>}
        <form className="discardPlan" onSubmit={prepare}>
          {!discardPlan&&<><label><span>일괄 폐기 사유</span><input value={reason} maxLength={500} onChange={event=>setReason(event.target.value)} placeholder="폐기 사유를 입력하세요"/></label><button disabled={discardPlanBusy||selectedIds.length===0||!reason.trim()}>{discardPlanBusy?"검토 준비 중…":`선택한 ${selectedIds.length}건 검토`}</button><small>최대 20건 · 검토 계획 생성 후 10분 이내 별도 승인이 필요합니다.</small></>}
          {discardPlan&&<div className={`discardReview ${discardPlan.status.toLowerCase()}`}><div><b>{planStatusLabel[discardPlan.status]} · {discardPlan.eventIds.length}건</b><small>{discardPlan.reason}</small><small>만료 {new Date(discardPlan.expiresAt).toLocaleString("ko-KR")}</small></div>{discardPlan.status==="PREPARED"?<><label><span>승인어 DISCARD 입력</span><input value={approval} onChange={event=>setApproval(event.target.value)} autoComplete="off"/></label><span className="discardApprovalActions"><button type="button" className="discard" disabled={discardPlanBusy||approval!=="DISCARD"} onClick={()=>onExecuteDiscard(discardPlan.id)}>{discardPlanBusy?"폐기 중…":"영구 폐기 실행"}</button><button type="button" disabled={discardPlanBusy} onClick={reset}>취소</button></span></>:<><strong>성공 {discardPlan.succeededCount}건 · 실패 {discardPlan.failedCount}건</strong><button type="button" onClick={reset}>새 계획</button></>}</div>}
        </form>
      </div>
      <div className="auditPane"><h4>복구 작업 이력</h4>
        {audits.length === 0 ? <p className="replayEmpty">재처리 또는 폐기 작업이 여기에 기록됩니다.</p> : audits.slice(0, 8).map((audit) => <div className="auditRow" key={audit.id}><span>{audit.action === "DISCARD" ? "×" : "↻"}</span><span><b>{auditActionLabel[audit.action]} · {audit.actor}</b><small>{audit.deadLetterEventId.slice(0, 8)} · {new Date(audit.occurredAt).toLocaleString("ko-KR")}</small>{audit.reason&&<small>{audit.reason}</small>}</span></div>)}
      </div>
    </div>
  </section>;
}

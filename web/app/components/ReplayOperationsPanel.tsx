import { FormEvent, useEffect, useMemo, useState } from "react";
import type { DeadLetterEvent, DiscardPlan, ReplayAudit } from "../types";

type Props = { events: DeadLetterEvent[]; totalEvents:number; audits: ReplayAudit[]; busyId?: string; pageBusy:boolean; discardPlan?: DiscardPlan; discardPlanBusy: boolean; onReplay: (id: string) => void; onDiscard: (id: string) => void; onLoadMore:()=>void; onPrepareDiscard: (ids:string[],reason:string) => void; onExecuteDiscard: (id:string) => void; onResetDiscardPlan: () => void };

const eventStatusLabel: Record<DeadLetterEvent["status"],string> = {PENDING:"복구 대기",REPLAYED:"재처리 완료",DISCARDED:"폐기 완료"};
const auditActionLabel: Record<ReplayAudit["action"],string> = {REPLAY:"재처리",DISCARD:"폐기"};
const planStatusLabel: Record<DiscardPlan["status"],string> = {PREPARED:"승인 대기",EXECUTED:"실행 완료",PARTIAL:"일부 완료",EXPIRED:"만료됨"};

function failureAge(failedAt:string){
  const elapsed=Math.max(0,Date.now()-new Date(failedAt).getTime());
  const minutes=Math.floor(elapsed/60_000);
  if(minutes<1)return "1분 미만";
  if(minutes<60)return `${minutes}분`;
  const hours=Math.floor(minutes/60);
  if(hours<24)return `${hours}시간`;
  return `${Math.floor(hours/24)}일`;
}

export default function ReplayOperationsPanel({ events, totalEvents, audits, busyId, pageBusy, discardPlan, discardPlanBusy, onReplay, onDiscard, onLoadMore, onPrepareDiscard, onExecuteDiscard, onResetDiscardPlan }: Props) {
  const pending = events.filter((event) => event.status === "PENDING");
  const replayed = events.filter((event) => event.status === "REPLAYED").length;
  const discarded = events.filter((event) => event.status === "DISCARDED").length;
  const [selectedIds,setSelectedIds]=useState<string[]>([]);
  const [reason,setReason]=useState("");
  const [approval,setApproval]=useState("");
  const [scope,setScope]=useState<"ALL"|DeadLetterEvent["status"]>("PENDING");
  const [sort,setSort]=useState<"NEWEST"|"OLDEST">("NEWEST");
  const [query,setQuery]=useState("");
  const [auditQuery,setAuditQuery]=useState("");
  const [visibleAudits,setVisibleAudits]=useState(8);
  const filteredEvents=useMemo(()=>{
    const normalizedQuery=query.trim().toLowerCase();
    return events.filter(event=>(scope==="ALL"||event.status===scope)&&(!normalizedQuery||[event.originalTopic,event.traceId||"",event.messageKey||"",event.exceptionMessage||""].some(value=>value.toLowerCase().includes(normalizedQuery))))
      .sort((left,right)=>(sort==="OLDEST"?1:-1)*(new Date(left.failedAt).getTime()-new Date(right.failedAt).getTime()));
  },[events,query,scope,sort]);
  const filteredAudits=useMemo(()=>{
    const normalizedQuery=auditQuery.trim().toLowerCase();
    return normalizedQuery?audits.filter(audit=>[audit.actor,audit.deadLetterEventId,auditActionLabel[audit.action],audit.reason||""].some(value=>value.toLowerCase().includes(normalizedQuery))):audits;
  },[auditQuery,audits]);
  const shownAudits=filteredAudits.slice(0,visibleAudits);
  useEffect(()=>setVisibleAudits(8),[auditQuery]);
  useEffect(()=>setVisibleAudits(current=>Math.min(Math.max(current,8),Math.max(filteredAudits.length,8))),[filteredAudits.length]);
  useEffect(()=>setSelectedIds(current=>current.filter(id=>events.some(event=>event.id===id&&event.status==="PENDING"))),[events]);
  const toggle=(id:string)=>setSelectedIds(current=>current.includes(id)?current.filter(value=>value!==id):current.length<20?[...current,id]:current);
  const replayEvent=(event:DeadLetterEvent)=>{
    const identifier=event.traceId||event.messageKey||event.id;
    if(window.confirm(`${identifier} 이벤트를 재처리하시겠습니까? 성공한 작업은 복구 감사 이력에 기록됩니다.`)) onReplay(event.id);
  };
  const discardEvent=(event:DeadLetterEvent)=>{
    const identifier=event.traceId||event.messageKey||event.id;
    if(window.confirm(`${identifier} 이벤트를 영구 폐기하시겠습니까? 이 작업은 되돌릴 수 없으며 복구 감사 이력에 기록됩니다.`)) onDiscard(event.id);
  };
  const prepare=(event:FormEvent)=>{event.preventDefault();onPrepareDiscard(selectedIds,reason)};
  const reset=()=>{setSelectedIds([]);setReason("");setApproval("");onResetDiscardPlan()};
  return <section className="replayBoard">
    <div className="replayHeader"><div><p className="eyebrow">복구 / 격리 이벤트</p><h2>실패 이벤트 검토</h2></div><div><b>{totalEvents}</b><span>복구 대기 · {pending.length}건 불러옴</span></div></div>
    <div className="replayColumns">
      <div className="deadLetters"><div className="recoveryPaneHeader dlqPaneHeader"><h4>격리된 이벤트</h4><label htmlFor="dlqScope"><span>상태</span><select id="dlqScope" value={scope} onChange={event=>setScope(event.target.value as "ALL"|DeadLetterEvent["status"])}><option value="PENDING">복구 대기 {pending.length}</option><option value="REPLAYED">재처리 완료 {replayed}</option><option value="DISCARDED">폐기 완료 {discarded}</option><option value="ALL">전체 {events.length}</option></select></label><label htmlFor="dlqSort"><span>정렬</span><select id="dlqSort" value={sort} onChange={event=>setSort(event.target.value as "NEWEST"|"OLDEST")}><option value="NEWEST">최근 실패순</option><option value="OLDEST">오래된 실패순</option></select></label><label htmlFor="dlqSearch"><span>불러온 이벤트 검색</span><input id="dlqSearch" type="search" value={query} onChange={event=>setQuery(event.target.value)} placeholder="토픽 · trace ID · 오류"/></label>{(query||scope!=="PENDING")&&<><span className="alertFilterResult" aria-live="polite">{filteredEvents.length}건</span><button type="button" onClick={()=>{setQuery("");setScope("PENDING")}}>초기화</button></>}</div>
        {events.length === 0 ? <p className="replayEmpty">격리된 telemetry 이벤트가 없습니다.</p> : filteredEvents.length===0?<p className="replayEmpty">현재 상태와 검색 조건에 맞는 불러온 이벤트가 없습니다.</p>:filteredEvents.map((event) => <div className={`deadLetterRow ${selectedIds.includes(event.id)?"selected":""}`} key={event.id}>
          <input className="discardSelect" type="checkbox" aria-label={`${event.traceId||event.id} 일괄 폐기 선택`} checked={selectedIds.includes(event.id)} disabled={Boolean(discardPlan)||(!selectedIds.includes(event.id)&&selectedIds.length>=20)} onChange={()=>toggle(event.id)}/>
          <span className={`replayState ${event.status.toLowerCase()}`}>{eventStatusLabel[event.status]}</span>
          <span><b>{event.originalTopic}</b><small>{event.traceId || event.messageKey || event.id.slice(0, 8)} · 파티션 {event.dlqPartition} / 오프셋 {event.dlqOffset}</small><small>실패 {new Date(event.failedAt).toLocaleString("ko-KR")} · {failureAge(event.failedAt)} 경과</small><em>{event.exceptionMessage || "이벤트 처리에 실패했습니다."}</em></span>
          <span className="replayActions"><button disabled={event.status !== "PENDING" || busyId === event.id} onClick={() => replayEvent(event)} aria-label={`${event.traceId||event.id} 재처리`}>{busyId === event.id ? "처리 중…" : "재처리"}</button><button className="discard" disabled={event.status !== "PENDING" || busyId === event.id} onClick={() => discardEvent(event)} aria-label={`${event.traceId||event.id} 영구 폐기`}>영구 폐기</button></span>
        </div>)}
        {events.length<totalEvents&&<button className="loadMoreDlq" disabled={pageBusy} onClick={onLoadMore}>{pageBusy?"불러오는 중…":`이전 이벤트 ${Math.min(100,totalEvents-events.length)}건 더 보기`}</button>}
        <form className="discardPlan" onSubmit={prepare}>
          {!discardPlan&&<><label><span>일괄 폐기 사유</span><input value={reason} maxLength={500} onChange={event=>setReason(event.target.value)} placeholder="폐기 사유를 입력하세요"/></label><button disabled={discardPlanBusy||selectedIds.length===0||!reason.trim()}>{discardPlanBusy?"검토 준비 중…":`선택한 ${selectedIds.length}건 검토`}</button><small>단건 재처리·폐기도 대상 확인 후 실행됩니다. 일괄 폐기는 최대 20건이며 계획 생성 후 10분 이내 별도 승인이 필요합니다.</small></>}
          {discardPlan&&<div className={`discardReview ${discardPlan.status.toLowerCase()}`}><div><b>{planStatusLabel[discardPlan.status]} · {discardPlan.eventIds.length}건</b><small>{discardPlan.reason}</small><small>만료 {new Date(discardPlan.expiresAt).toLocaleString("ko-KR")}</small></div>{discardPlan.status==="PREPARED"?<><label><span>승인어 DISCARD 입력</span><input value={approval} onChange={event=>setApproval(event.target.value)} autoComplete="off"/></label><span className="discardApprovalActions"><button type="button" className="discard" disabled={discardPlanBusy||approval!=="DISCARD"} onClick={()=>onExecuteDiscard(discardPlan.id)}>{discardPlanBusy?"폐기 중…":"영구 폐기 실행"}</button><button type="button" disabled={discardPlanBusy} onClick={reset}>취소</button></span></>:<><strong>성공 {discardPlan.succeededCount}건 · 실패 {discardPlan.failedCount}건</strong><button type="button" onClick={reset}>새 계획</button></>}</div>}
        </form>
      </div>
      <div className="auditPane"><div className="recoveryPaneHeader"><h4>복구 작업 이력</h4><label htmlFor="dlqAuditSearch"><span>작업 이력 검색</span><input id="dlqAuditSearch" type="search" value={auditQuery} onChange={event=>setAuditQuery(event.target.value)} placeholder="작업자 · 이벤트 ID · 사유"/></label>{auditQuery&&<button type="button" onClick={()=>setAuditQuery("")}>초기화</button>}</div>
        {audits.length === 0 ? <p className="replayEmpty">재처리 또는 폐기 작업이 여기에 기록됩니다.</p> : filteredAudits.length===0?<p className="replayEmpty">검색 조건에 맞는 복구 작업 이력이 없습니다.</p>:shownAudits.map((audit) => <div className="auditRow" key={audit.id}><span>{audit.action === "DISCARD" ? "×" : "↻"}</span><span><b>{auditActionLabel[audit.action]} · {audit.actor}</b><small>{audit.deadLetterEventId.slice(0, 8)} · {new Date(audit.occurredAt).toLocaleString("ko-KR")}</small>{audit.reason&&<small>{audit.reason}</small>}</span></div>)}
        {filteredAudits.length>8&&<div className="policyAuditFooter"><span aria-live="polite">이력 {shownAudits.length} / {filteredAudits.length}건 표시</span>{shownAudits.length<filteredAudits.length?<button type="button" onClick={()=>setVisibleAudits(current=>Math.min(current+8,filteredAudits.length))}>다음 {Math.min(8,filteredAudits.length-shownAudits.length)}건 보기</button>:<button type="button" onClick={()=>setVisibleAudits(8)}>최근 8건만 보기</button>}</div>}
      </div>
    </div>
  </section>;
}

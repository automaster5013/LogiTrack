import { useEffect, useMemo, useState } from "react";
import type { Delivery, DeliveryAlert } from "../types";

type Props = {
  alerts: DeliveryAlert[];
  deliveries: Delivery[];
  busyId?: string;
  onSelect: (deliveryId: string) => void;
  onAcknowledge: (alertId: string) => void;
};

const alertStatusLabel: Record<DeliveryAlert["status"],string> = {ACTIVE:"대응 필요",RESOLVED:"해결됨"};
const alertTypeLabel: Record<DeliveryAlert["alertType"],string> = {DELAY:"도착 지연",ROUTE_DEVIATION:"경로 이탈"};
const alertSeverityLabel: Record<DeliveryAlert["severity"],string> = {WARNING:"주의",CRITICAL:"긴급"};
const formatAlertTime=(value:string)=>new Date(value).toLocaleString("ko-KR",{month:"numeric",day:"numeric",hour:"2-digit",minute:"2-digit"});
const formatAlertDuration=(first:string,last:string)=>{
  const totalMinutes=Math.floor(Math.max(0,new Date(last).getTime()-new Date(first).getTime())/60_000);
  if(totalMinutes<1)return "1분 미만";
  if(totalMinutes<60)return `${totalMinutes}분`;
  const totalHours=Math.floor(totalMinutes/60);
  if(totalHours<24)return `${totalHours}시간 ${totalMinutes%60}분`;
  return `${Math.floor(totalHours/24)}일 ${totalHours%24}시간`;
};

export default function AlertOperationsPanel({alerts,deliveries,busyId,onSelect,onAcknowledge}:Props){
  const [scope,setScope]=useState<"ACTIVE"|"ALL">("ACTIVE");
  const [severity,setSeverity]=useState<"ALL"|DeliveryAlert["severity"]>("ALL");
  const [alertType,setAlertType]=useState<"ALL"|DeliveryAlert["alertType"]>("ALL");
  const [acknowledgement,setAcknowledgement]=useState<"ALL"|"UNACKNOWLEDGED"|"ACKNOWLEDGED">("ALL");
  const [occurrence,setOccurrence]=useState<"ALL"|"REPEATED">("ALL");
  const [sort,setSort]=useState<"PRIORITY"|"RECENT"|"LONGEST"|"FREQUENT">("PRIORITY");
  const [query,setQuery]=useState("");
  const [visibleCount,setVisibleCount]=useState(8);
  const active=alerts.filter(alert=>alert.status==="ACTIVE");
  const unacknowledged=active.filter(alert=>!alert.acknowledgedAt);
  const alertsInScope=scope==="ACTIVE"?active:alerts;
  const delayAlerts=alertsInScope.filter(alert=>alert.alertType==="DELAY").length;
  const routeDeviationAlerts=alertsInScope.filter(alert=>alert.alertType==="ROUTE_DEVIATION").length;
  const criticalAlerts=alertsInScope.filter(alert=>alert.severity==="CRITICAL").length;
  const warningAlerts=alertsInScope.filter(alert=>alert.severity==="WARNING").length;
  const unacknowledgedAlerts=alertsInScope.filter(alert=>!alert.acknowledgedAt).length;
  const acknowledgedAlerts=alertsInScope.filter(alert=>Boolean(alert.acknowledgedAt)).length;
  const repeatedAlerts=alertsInScope.filter(alert=>alert.occurrenceCount>1).length;
  const scopedAlerts=useMemo(()=>{
    const normalizedQuery=query.trim().toLowerCase();
    return alerts.filter(alert=>{
      const delivery=deliveries.find(item=>item.id===alert.deliveryId);
      const matchesAcknowledgement=acknowledgement==="ALL"||(acknowledgement==="ACKNOWLEDGED"?Boolean(alert.acknowledgedAt):!alert.acknowledgedAt);
      return (scope==="ALL"||alert.status==="ACTIVE")&&(severity==="ALL"||alert.severity===severity)&&(alertType==="ALL"||alert.alertType===alertType)&&matchesAcknowledgement&&(occurrence==="ALL"||alert.occurrenceCount>1)&&(!normalizedQuery||[delivery?.vehicleId||"",delivery?.orderNumber||"",alert.message,alertTypeLabel[alert.alertType],alert.acknowledgedBy||""].some(value=>value.toLowerCase().includes(normalizedQuery)));
    }).sort((left,right)=>{
      if(sort==="RECENT")return new Date(right.lastObservedAt).getTime()-new Date(left.lastObservedAt).getTime();
      if(sort==="FREQUENT"&&right.occurrenceCount!==left.occurrenceCount)return right.occurrenceCount-left.occurrenceCount;
      if(sort==="LONGEST"){
        const leftDuration=new Date(left.lastObservedAt).getTime()-new Date(left.firstObservedAt).getTime();
        const rightDuration=new Date(right.lastObservedAt).getTime()-new Date(right.firstObservedAt).getTime();
        if(rightDuration!==leftDuration)return rightDuration-leftDuration;
      }
      const statusOrder=Number(left.status!=="ACTIVE")-Number(right.status!=="ACTIVE");
      if(statusOrder)return statusOrder;
      if(left.status==="RESOLVED"&&right.status==="RESOLVED"){
        const resolvedAtOrder=new Date(right.resolvedAt||right.lastObservedAt).getTime()-new Date(left.resolvedAt||left.lastObservedAt).getTime();
        if(resolvedAtOrder)return resolvedAtOrder;
      }
      const acknowledgementOrder=Number(Boolean(left.acknowledgedAt))-Number(Boolean(right.acknowledgedAt));
      if(acknowledgementOrder)return acknowledgementOrder;
      if(left.acknowledgedAt&&right.acknowledgedAt){
        const acknowledgedAtOrder=new Date(right.acknowledgedAt).getTime()-new Date(left.acknowledgedAt).getTime();
        if(acknowledgedAtOrder)return acknowledgedAtOrder;
      }
      const severityOrder=Number(left.severity!=="CRITICAL")-Number(right.severity!=="CRITICAL");
      if(severityOrder)return severityOrder;
      return new Date(right.lastObservedAt).getTime()-new Date(left.lastObservedAt).getTime();
    });
  },[acknowledgement,alertType,alerts,deliveries,occurrence,query,scope,severity,sort]);
  const visibleAlerts=scopedAlerts.slice(0,visibleCount);
  const remaining=Math.max(0,scopedAlerts.length-visibleAlerts.length);

  useEffect(()=>{
    setVisibleCount(8);
  },[acknowledgement,alertType,occurrence,query,scope,severity,sort]);

  useEffect(()=>{
    setVisibleCount(current=>Math.max(8,Math.min(current,Math.max(scopedAlerts.length,8))));
  },[scopedAlerts.length]);

  return <section className="alertBoard">
    <div className="alertHeader"><div><p className="eyebrow">예외 상황 관리</p><h2>배송 경고</h2></div>
      <div className="alertHeaderMeta"><div className="alertHeaderStats"><span><b>{active.length}</b><small>대응 필요</small></span><span><b>{unacknowledged.length}</b><small>미확인</small></span></div>
        <div className="alertScope" aria-label="경고 표시 범위"><button type="button" aria-pressed={scope==="ACTIVE"} onClick={()=>setScope("ACTIVE")}>현재 경고 {active.length}</button><button type="button" aria-pressed={scope==="ALL"} onClick={()=>setScope("ALL")}>전체 이력 {alerts.length}</button></div>
        <label className="alertFilter" htmlFor="alertType"><span>경고 유형</span><select id="alertType" value={alertType} onChange={event=>setAlertType(event.target.value as "ALL"|DeliveryAlert["alertType"])}><option value="ALL">전체 {alertsInScope.length}</option><option value="DELAY">도착 지연 {delayAlerts}</option><option value="ROUTE_DEVIATION">경로 이탈 {routeDeviationAlerts}</option></select></label>
        <label className="alertFilter" htmlFor="alertSeverity"><span>심각도</span><select id="alertSeverity" value={severity} onChange={event=>setSeverity(event.target.value as "ALL"|DeliveryAlert["severity"])}><option value="ALL">전체 {alertsInScope.length}</option><option value="CRITICAL">긴급 {criticalAlerts}</option><option value="WARNING">주의 {warningAlerts}</option></select></label>
        <label className="alertFilter" htmlFor="alertAcknowledgement"><span>확인 상태</span><select id="alertAcknowledgement" value={acknowledgement} onChange={event=>setAcknowledgement(event.target.value as "ALL"|"UNACKNOWLEDGED"|"ACKNOWLEDGED")}><option value="ALL">전체 {alertsInScope.length}</option><option value="UNACKNOWLEDGED">미확인 {unacknowledgedAlerts}</option><option value="ACKNOWLEDGED">확인 완료 {acknowledgedAlerts}</option></select></label>
        <label className="alertFilter" htmlFor="alertOccurrence"><span>감지 횟수</span><select id="alertOccurrence" value={occurrence} onChange={event=>setOccurrence(event.target.value as "ALL"|"REPEATED")}><option value="ALL">전체 {alertsInScope.length}</option><option value="REPEATED">반복 감지 {repeatedAlerts}</option></select></label>
        <label className="alertFilter" htmlFor="alertSort"><span>정렬</span><select id="alertSort" value={sort} onChange={event=>setSort(event.target.value as "PRIORITY"|"RECENT"|"LONGEST"|"FREQUENT")}><option value="PRIORITY">대응 우선순위</option><option value="RECENT">최근 감지순</option><option value="LONGEST">지속 시간순</option><option value="FREQUENT">감지 횟수순</option></select></label>
        <label className="alertSearch" htmlFor="alertSearch"><span>경고 검색</span><input id="alertSearch" type="search" value={query} onChange={event=>setQuery(event.target.value)} placeholder="차량 · 주문 · 내용 · 담당자"/></label>
        {(query||alertType!=="ALL"||severity!=="ALL"||acknowledgement!=="ALL"||occurrence!=="ALL")&&<span className="alertFilterResult" aria-live="polite">{scopedAlerts.length}건</span>}
        {(query||alertType!=="ALL"||severity!=="ALL"||acknowledgement!=="ALL"||occurrence!=="ALL")&&<button type="button" className="alertReset" onClick={()=>{setQuery("");setAlertType("ALL");setSeverity("ALL");setAcknowledgement("ALL");setOccurrence("ALL")}}>초기화</button>}
      </div>
    </div>
    <div className="alertGrid">{scopedAlerts.length===0?<div className="alertEmpty">{query||alertType!=="ALL"||severity!=="ALL"||acknowledgement!=="ALL"||occurrence!=="ALL"?"현재 범위와 검색 조건에 맞는 경고가 없습니다.":scope==="ACTIVE"?"현재 대응이 필요한 경고가 없습니다. 해결된 경고는 ‘전체 이력’에서 확인할 수 있습니다.":"감지된 지연 또는 경로 이탈 이력이 없습니다."}</div>:visibleAlerts.map(alert=>{
      const delivery=deliveries.find(item=>item.id===alert.deliveryId);
      return <div key={alert.id} className={`alertCard ${alert.status.toLowerCase()} ${alert.severity.toLowerCase()} ${alert.acknowledgedAt?"acknowledged":""}`}>
        <button className="alertFocus" onClick={()=>onSelect(alert.deliveryId)} aria-label={`${delivery?.vehicleId||alert.deliveryId}${delivery?.orderNumber?` 주문 ${delivery.orderNumber}`:""} 지도에서 보기`}>
          <span className="alertState">{alertStatusLabel[alert.status]}{alert.status==="RESOLVED"&&alert.resolvedAt?` · ${formatAlertTime(alert.resolvedAt)}`:""}</span><span className="alertKind">{alertTypeLabel[alert.alertType]} · {alertSeverityLabel[alert.severity]}</span>
          <strong>{delivery?.vehicleId||alert.deliveryId.slice(0,8)}</strong>{delivery?.orderNumber?<span className="alertOrder">주문 {delivery.orderNumber}</span>:null}<p>{alert.message}</p>
          <small>{alert.occurrenceCount}회 감지 · 지속 {formatAlertDuration(alert.firstObservedAt,alert.lastObservedAt)} · 최초 {formatAlertTime(alert.firstObservedAt)} · 최근 {formatAlertTime(alert.lastObservedAt)}</small>
        </button>
        {alert.status==="ACTIVE"&&!alert.acknowledgedAt?<button className="alertAck" disabled={busyId===alert.id} onClick={()=>onAcknowledge(alert.id)} aria-label={`${delivery?.vehicleId||alert.deliveryId}${delivery?.orderNumber?` 주문 ${delivery.orderNumber}`:""} 경고 확인 처리`}>{busyId===alert.id?"확인 처리 중…":"확인 완료"}</button>
          :alert.acknowledgedAt?<span className="alertAcknowledged">확인 · {alert.acknowledgedBy} · {formatAlertTime(alert.acknowledgedAt)}</span>:null}
      </div>})}
      {scopedAlerts.length>8?<div className="alertListFooter">
        <span aria-live="polite">경고 {visibleAlerts.length} / {scopedAlerts.length}건 표시</span>
        {remaining>0?<button type="button" onClick={()=>setVisibleCount(current=>Math.min(current+8,scopedAlerts.length))}>다음 {Math.min(8,remaining)}건 보기</button>:<button type="button" onClick={()=>setVisibleCount(8)}>최근 8건만 보기</button>}
      </div>:null}
    </div>
  </section>;
}

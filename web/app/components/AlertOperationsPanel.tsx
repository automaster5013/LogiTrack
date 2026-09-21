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

export default function AlertOperationsPanel({alerts,deliveries,busyId,onSelect,onAcknowledge}:Props){
  const [scope,setScope]=useState<"ACTIVE"|"ALL">("ACTIVE");
  const [severity,setSeverity]=useState<"ALL"|DeliveryAlert["severity"]>("ALL");
  const [query,setQuery]=useState("");
  const [visibleCount,setVisibleCount]=useState(8);
  const active=alerts.filter(alert=>alert.status==="ACTIVE");
  const unacknowledged=active.filter(alert=>!alert.acknowledgedAt);
  const scopedAlerts=useMemo(()=>{
    const normalizedQuery=query.trim().toLowerCase();
    return alerts.filter(alert=>{
      const delivery=deliveries.find(item=>item.id===alert.deliveryId);
      return (scope==="ALL"||alert.status==="ACTIVE")&&(severity==="ALL"||alert.severity===severity)&&(!normalizedQuery||[delivery?.vehicleId||"",delivery?.orderNumber||"",alert.message,alertTypeLabel[alert.alertType]].some(value=>value.toLowerCase().includes(normalizedQuery)));
    });
  },[alerts,deliveries,query,scope,severity]);
  const visibleAlerts=scopedAlerts.slice(0,visibleCount);
  const remaining=Math.max(0,scopedAlerts.length-visibleAlerts.length);

  useEffect(()=>{
    setVisibleCount(8);
  },[query,scope,severity]);

  useEffect(()=>{
    setVisibleCount(current=>Math.max(8,Math.min(current,Math.max(scopedAlerts.length,8))));
  },[scopedAlerts.length]);

  return <section className="alertBoard">
    <div className="alertHeader"><div><p className="eyebrow">예외 상황 관리</p><h2>배송 경고</h2></div>
      <div className="alertHeaderMeta"><div className="alertHeaderStats"><span><b>{active.length}</b><small>대응 필요</small></span><span><b>{unacknowledged.length}</b><small>미확인</small></span></div>
        <div className="alertScope" aria-label="경고 표시 범위"><button type="button" aria-pressed={scope==="ACTIVE"} onClick={()=>setScope("ACTIVE")}>현재 경고 {active.length}</button><button type="button" aria-pressed={scope==="ALL"} onClick={()=>setScope("ALL")}>전체 이력 {alerts.length}</button></div>
        <label className="alertFilter" htmlFor="alertSeverity"><span>심각도</span><select id="alertSeverity" value={severity} onChange={event=>setSeverity(event.target.value as "ALL"|DeliveryAlert["severity"])}><option value="ALL">전체</option><option value="CRITICAL">긴급</option><option value="WARNING">주의</option></select></label>
        <label className="alertSearch" htmlFor="alertSearch"><span>경고 검색</span><input id="alertSearch" type="search" value={query} onChange={event=>setQuery(event.target.value)} placeholder="차량 · 주문 · 내용"/></label>
        {(query||severity!=="ALL")&&<button type="button" className="alertReset" onClick={()=>{setQuery("");setSeverity("ALL")}}>초기화</button>}
      </div>
    </div>
    <div className="alertGrid">{scopedAlerts.length===0?<div className="alertEmpty">{query||severity!=="ALL"?"현재 범위와 검색 조건에 맞는 경고가 없습니다.":scope==="ACTIVE"?"현재 대응이 필요한 경고가 없습니다. 해결된 경고는 ‘전체 이력’에서 확인할 수 있습니다.":"감지된 지연 또는 경로 이탈 이력이 없습니다."}</div>:visibleAlerts.map(alert=>{
      const delivery=deliveries.find(item=>item.id===alert.deliveryId);
      return <div key={alert.id} className={`alertCard ${alert.status.toLowerCase()} ${alert.severity.toLowerCase()} ${alert.acknowledgedAt?"acknowledged":""}`}>
        <button className="alertFocus" onClick={()=>onSelect(alert.deliveryId)} aria-label={`${delivery?.vehicleId||alert.deliveryId} 지도에서 보기`}>
          <span className="alertState">{alertStatusLabel[alert.status]}</span><span className="alertKind">{alertTypeLabel[alert.alertType]} · {alertSeverityLabel[alert.severity]}</span>
          <strong>{delivery?.vehicleId||alert.deliveryId.slice(0,8)}</strong><p>{alert.message}</p>
          <small>{alert.occurrenceCount}회 감지 · 최근 {new Date(alert.lastObservedAt).toLocaleTimeString("ko-KR",{hour:"2-digit",minute:"2-digit"})}</small>
        </button>
        {alert.status==="ACTIVE"&&!alert.acknowledgedAt?<button className="alertAck" disabled={busyId===alert.id} onClick={()=>onAcknowledge(alert.id)} aria-label={`${delivery?.vehicleId||alert.deliveryId} 경고 확인 처리`}>{busyId===alert.id?"확인 처리 중…":"확인 완료"}</button>
          :alert.acknowledgedAt?<span className="alertAcknowledged">확인 · {alert.acknowledgedBy}</span>:null}
      </div>})}
      {scopedAlerts.length>8?<div className="alertListFooter">
        <span aria-live="polite">경고 {visibleAlerts.length} / {scopedAlerts.length}건 표시</span>
        {remaining>0?<button type="button" onClick={()=>setVisibleCount(current=>Math.min(current+8,scopedAlerts.length))}>다음 {Math.min(8,remaining)}건 보기</button>:<button type="button" onClick={()=>setVisibleCount(8)}>최근 8건만 보기</button>}
      </div>:null}
    </div>
  </section>;
}

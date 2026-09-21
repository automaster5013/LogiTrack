import { useEffect, useState } from "react";
import type { Delivery, DeliveryAlert } from "../types";

type Props = {
  deliveries: Delivery[];
  activeAlerts: DeliveryAlert[];
  selectedId?: string;
  scope: "LIVE" | "ATTENTION" | "ALL";
  query: string;
  liveDeliveries: number;
  attentionDeliveries: number;
  totalDeliveries: number;
  onSelect: (deliveryId: string) => void;
  onScopeChange: (scope: "LIVE" | "ATTENTION" | "ALL") => void;
  onQueryChange: (query: string) => void;
};

const deliveryStatusLabel: Record<Delivery["status"],string> = {
  CREATED: "배송 준비",
  IN_TRANSIT: "운송 중",
  DELAYED: "지연",
  DELIVERED: "배송 완료"
};

function deliveryTiming(delivery:Delivery){
  if(delivery.status==="DELIVERED")return {label:"배송 완료",overdue:false};
  if(delivery.eta){
    const eta=new Date(delivery.eta);
    if(!Number.isNaN(eta.getTime())){
      const time=eta.toLocaleTimeString("ko-KR",{hour:"2-digit",minute:"2-digit"});
      const overdue=eta.getTime()<Date.now();
      return {label:`도착 예정 ${time}${overdue?" · 예정 초과":""}`,overdue};
    }
  }
  const hasPosition=delivery.currentLat!=null&&delivery.currentLon!=null;
  return {label:hasPosition?"위치 수신됨":"위치 수신 대기",overdue:false};
}

export default function FleetTelemetryPanel({deliveries,activeAlerts,selectedId,scope,query,liveDeliveries,attentionDeliveries,totalDeliveries,onSelect,onScopeChange,onQueryChange}:Props){
  const [visibleCount,setVisibleCount]=useState(15);
  const visibleDeliveries=deliveries.slice(0,visibleCount);
  const remaining=deliveries.length-visibleDeliveries.length;

  useEffect(()=>setVisibleCount(15),[scope,query]);
  useEffect(()=>setVisibleCount(current=>Math.max(15,Math.min(current,Math.max(deliveries.length,15)))),[deliveries.length]);

  return <section className="board"><div className="boardTitle fleetBoardHeader"><div><h2>차량 운행 현황</h2><span>{visibleDeliveries.length} / {deliveries.length}건 표시 · 전체 {totalDeliveries}건</span></div><div className="fleetToolbar"><div className="fleetScope" aria-label="차량 목록 표시 범위"><button type="button" aria-pressed={scope==="LIVE"} onClick={()=>onScopeChange("LIVE")}>진행 중 {liveDeliveries}</button><button type="button" aria-pressed={scope==="ATTENTION"} onClick={()=>onScopeChange("ATTENTION")}>확인 필요 {attentionDeliveries}</button><button type="button" aria-pressed={scope==="ALL"} onClick={()=>onScopeChange("ALL")}>전체 {totalDeliveries}</button></div><label className="fleetSearch" htmlFor="fleetListSearch"><span>차량 검색</span><input id="fleetListSearch" type="search" value={query} onChange={event=>onQueryChange(event.target.value)} placeholder="차량 · 주문 · 지역"/></label>{query&&<button type="button" className="fleetClear" onClick={()=>onQueryChange("")}>검색 초기화</button>}</div></div>
    <div className="grid">{deliveries.length===0?<div className="empty">{totalDeliveries===0?"배송을 생성하면 차량 위치 이벤트가 지도와 목록에 표시됩니다.":"현재 범위와 검색 조건에 맞는 배송이 없습니다."}</div>:visibleDeliveries.map(delivery=>{const count=activeAlerts.filter(alert=>alert.deliveryId===delivery.id).length;const isSelected=selectedId===delivery.id;const timing=deliveryTiming(delivery);return <article key={delivery.id} role="button" tabIndex={0} aria-current={isSelected?"true":undefined} aria-label={`${delivery.vehicleId}, ${delivery.originName}에서 ${delivery.destinationName}, ${deliveryStatusLabel[delivery.status]}, ${Math.round(delivery.progress*100)}% 진행, ${timing.label}${count?`, 경고 ${count}건`:""}`} onClick={()=>onSelect(delivery.id)} onKeyDown={event=>{if(event.key==="Enter"||event.key===" "){event.preventDefault();onSelect(delivery.id)}}} className={isSelected?"selected":""}><div className="row"><span className={`badge ${delivery.status.toLowerCase()}`}>{deliveryStatusLabel[delivery.status]}</span><b>{count>0&&<i className="cardAlert" aria-hidden="true">{count}</i>}{delivery.vehicleId}</b></div><h3>{delivery.orderNumber}</h3><p>{delivery.originName} <em>→</em> {delivery.destinationName}</p><div className="track" aria-hidden="true"><i style={{width:`${delivery.progress*100}%`}}/></div><div className="meta"><span>진행률 {Math.round(delivery.progress*100)}%</span><span className={timing.overdue?"fleetTimingOverdue":undefined}>{timing.label}</span></div></article>})}
      {deliveries.length>15&&<div className="fleetListFooter"><span aria-live="polite">차량 {visibleDeliveries.length} / {deliveries.length}건 표시</span>{remaining>0?<button type="button" onClick={()=>setVisibleCount(current=>Math.min(current+15,deliveries.length))}>다음 {Math.min(15,remaining)}건 보기</button>:<button type="button" onClick={()=>setVisibleCount(15)}>최근 15건만 보기</button>}</div>}
    </div>
  </section>;
}

import { useEffect, useState } from "react";
import type { Delivery, DeliveryAlert } from "../types";

type Props = {
  alerts: DeliveryAlert[];
  deliveries: Delivery[];
  busyId?: string;
  onSelect: (deliveryId: string) => void;
  onAcknowledge: (alertId: string) => void;
};

export default function AlertOperationsPanel({alerts,deliveries,busyId,onSelect,onAcknowledge}:Props){
  const [scope,setScope]=useState<"ACTIVE"|"ALL">("ACTIVE");
  const [visibleCount,setVisibleCount]=useState(8);
  const active=alerts.filter(alert=>alert.status==="ACTIVE");
  const unacknowledged=active.filter(alert=>!alert.acknowledgedAt);
  const scopedAlerts=scope==="ACTIVE"?active:alerts;
  const visibleAlerts=scopedAlerts.slice(0,visibleCount);
  const remaining=Math.max(0,scopedAlerts.length-visibleAlerts.length);

  useEffect(()=>{
    setVisibleCount(8);
  },[scope]);

  useEffect(()=>{
    setVisibleCount(current=>Math.max(8,Math.min(current,Math.max(scopedAlerts.length,8))));
  },[scopedAlerts.length]);

  return <section className="alertBoard">
    <div className="alertHeader"><div><p className="eyebrow">EXCEPTION MANAGEMENT</p><h2>Delivery alerts</h2></div>
      <div className="alertHeaderMeta"><div className="alertHeaderStats"><span><b>{active.length}</b><small>ACTIVE</small></span><span><b>{unacknowledged.length}</b><small>UNACKNOWLEDGED</small></span></div>
        <div className="alertScope" aria-label="경고 표시 범위"><button type="button" aria-pressed={scope==="ACTIVE"} onClick={()=>setScope("ACTIVE")}>현재 경고 {active.length}</button><button type="button" aria-pressed={scope==="ALL"} onClick={()=>setScope("ALL")}>전체 이력 {alerts.length}</button></div>
      </div>
    </div>
    <div className="alertGrid">{scopedAlerts.length===0?<div className="alertEmpty">{scope==="ACTIVE"?"현재 대응이 필요한 경고가 없습니다. 해결된 경고는 ‘전체 이력’에서 확인할 수 있습니다.":"감지된 지연 또는 경로 이탈 이력이 없습니다."}</div>:visibleAlerts.map(alert=>{
      const delivery=deliveries.find(item=>item.id===alert.deliveryId);
      return <div key={alert.id} className={`alertCard ${alert.status.toLowerCase()} ${alert.severity.toLowerCase()} ${alert.acknowledgedAt?"acknowledged":""}`}>
        <button className="alertFocus" onClick={()=>onSelect(alert.deliveryId)} aria-label={`${delivery?.vehicleId||alert.deliveryId} 지도에서 보기`}>
          <span className="alertState">{alert.status}</span><span className="alertKind">{alert.alertType.replace("_"," ")}</span>
          <strong>{delivery?.vehicleId||alert.deliveryId.slice(0,8)}</strong><p>{alert.message}</p>
          <small>{alert.occurrenceCount} observations · {new Date(alert.lastObservedAt).toLocaleTimeString("ko-KR",{hour:"2-digit",minute:"2-digit"})}</small>
        </button>
        {alert.status==="ACTIVE"&&!alert.acknowledgedAt?<button className="alertAck" disabled={busyId===alert.id} onClick={()=>onAcknowledge(alert.id)}>{busyId===alert.id?"ACKNOWLEDGING…":"ACKNOWLEDGE"}</button>
          :alert.acknowledgedAt?<span className="alertAcknowledged">ACK · {alert.acknowledgedBy}</span>:null}
      </div>})}
      {scopedAlerts.length>8?<div className="alertListFooter">
        <span aria-live="polite">경고 {visibleAlerts.length} / {scopedAlerts.length}건 표시</span>
        {remaining>0?<button type="button" onClick={()=>setVisibleCount(current=>Math.min(current+8,scopedAlerts.length))}>다음 {Math.min(8,remaining)}건 보기</button>:<button type="button" onClick={()=>setVisibleCount(8)}>최근 8건만 보기</button>}
      </div>:null}
    </div>
  </section>;
}

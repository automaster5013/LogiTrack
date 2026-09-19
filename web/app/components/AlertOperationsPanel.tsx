import type { Delivery, DeliveryAlert } from "../types";

type Props = {
  alerts: DeliveryAlert[];
  deliveries: Delivery[];
  busyId?: string;
  onSelect: (deliveryId: string) => void;
  onAcknowledge: (alertId: string) => void;
};

export default function AlertOperationsPanel({alerts,deliveries,busyId,onSelect,onAcknowledge}:Props){
  const active=alerts.filter(alert=>alert.status==="ACTIVE");
  const unacknowledged=active.filter(alert=>!alert.acknowledgedAt);
  return <section className="alertBoard">
    <div className="alertHeader"><div><p className="eyebrow">EXCEPTION MANAGEMENT</p><h2>Delivery alerts</h2></div>
      <div className="alertHeaderStats"><span><b>{active.length}</b><small>ACTIVE</small></span><span><b>{unacknowledged.length}</b><small>UNACKNOWLEDGED</small></span></div>
    </div>
    <div className="alertGrid">{alerts.length===0?<div className="alertEmpty">현재 감지된 지연 또는 경로 이탈이 없습니다.</div>:alerts.slice(0,8).map(alert=>{
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
    </div>
  </section>;
}

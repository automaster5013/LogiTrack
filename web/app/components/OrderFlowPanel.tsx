import { useEffect, useState } from "react";
import type { CustomerOrder } from "../types";

const orderStatusLabel:Record<CustomerOrder["status"],string>={READY:"배차 대기",DISPATCHED:"운송 중",FULFILLED:"배송 완료"};
const deliveryStatusLabel:Record<string,string>={CREATED:"배송 준비",IN_TRANSIT:"운송 중",DELAYED:"지연",DELIVERED:"배송 완료"};

type Props = {
  orders: CustomerOrder[];
  busyId?: string;
  onCreate: () => void;
  onDispatch: (id: string) => void;
};

export default function OrderFlowPanel({ orders, busyId, onCreate, onDispatch }: Props) {
  const [visibleCount, setVisibleCount] = useState(8);
  const ready=orders.filter(order=>order.status==="READY").length;
  const dispatched=orders.filter(order=>order.status==="DISPATCHED").length;
  const fulfilled=orders.filter(order=>order.status==="FULFILLED").length;
  const visibleOrders=orders.slice(0,visibleCount);
  const remaining=Math.max(0,orders.length-visibleOrders.length);

  useEffect(() => {
    setVisibleCount(current => Math.max(8, Math.min(current, Math.max(orders.length, 8))));
  }, [orders.length]);

  return <section className="orderBoard">
    <div className="orderHeader">
      <div><p className="eyebrow">주문 처리</p><h2>주문 → 배송 흐름</h2></div>
      <button disabled={Boolean(busyId)} onClick={onCreate}>+ 새 주문</button>
    </div>
    <div className="orderStats"><span><b>{ready}</b> 배차 대기</span><span><b>{dispatched}</b> 운송 중</span><span><b>{fulfilled}</b> 배송 완료</span><small>등록 주문 {orders.length}건 기준 · 차량 현황은 전체 배송 기준</small></div>
    <div className="orderList">
      {orders.length===0?<p className="orderEmpty">새 주문을 만들면 배차 흐름이 여기에 표시됩니다.</p>:visibleOrders.map(order=><div className="orderRow" key={order.id}>
        <span className={`orderState ${order.status.toLowerCase()}`}>{orderStatusLabel[order.status]}</span>
        <span className="orderIdentity"><b>{order.orderNumber}</b><small>{order.originName} → {order.destinationName}</small></span>
        <span className="orderLink">{order.deliveryId?<><b>{order.vehicleId}</b><small>배차 차량</small></>:<><b>미배차</b><small>차량 배차 대기</small></>}</span>
        {order.status==="READY"?<button disabled={Boolean(busyId)} onClick={()=>onDispatch(order.id)} aria-label={`${order.orderNumber} 차량 배차`}>{busyId===order.id?"배차 중…":"차량 배차"}</button>:<span className="orderProgress"><i className={(order.deliveryStatus||order.status).toLowerCase()}/>{deliveryStatusLabel[order.deliveryStatus||""]||orderStatusLabel[order.status]}</span>}
      </div>)}
      {orders.length>8?<div className="orderListFooter">
        <span>{visibleOrders.length} / {orders.length}건 표시</span>
        {remaining>0?<button type="button" onClick={()=>setVisibleCount(current=>Math.min(current+8,orders.length))}>다음 {Math.min(8,remaining)}건 보기</button>:<button type="button" onClick={()=>setVisibleCount(8)}>최근 8건만 보기</button>}
      </div>:null}
    </div>
  </section>;
}

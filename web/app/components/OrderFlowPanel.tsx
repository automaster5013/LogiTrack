import { useEffect, useMemo, useState } from "react";
import type { CustomerOrder } from "../types";

const orderStatusLabel:Record<CustomerOrder["status"],string>={READY:"배차 대기",DISPATCHED:"운송 중",FULFILLED:"배송 완료"};
const deliveryStatusLabel:Record<string,string>={CREATED:"배송 준비",IN_TRANSIT:"운송 중",DELAYED:"지연",DELIVERED:"배송 완료"};
const formatOrderTime=(value:string)=>new Date(value).toLocaleString("ko-KR",{month:"numeric",day:"numeric",hour:"2-digit",minute:"2-digit"});

type Props = {
  orders: CustomerOrder[];
  busyId?: string;
  onCreate: () => void;
  onDispatch: (id: string) => void;
  onSelectDelivery: (id: string) => void;
};

export default function OrderFlowPanel({ orders, busyId, onCreate, onDispatch, onSelectDelivery }: Props) {
  const [scope, setScope] = useState<"ALL"|CustomerOrder["status"]>("ALL");
  const [query, setQuery] = useState("");
  const [visibleCount, setVisibleCount] = useState(8);
  const ready=orders.filter(order=>order.status==="READY").length;
  const dispatched=orders.filter(order=>order.status==="DISPATCHED").length;
  const fulfilled=orders.filter(order=>order.status==="FULFILLED").length;
  const filteredOrders=useMemo(()=>{
    const normalizedQuery=query.trim().toLowerCase();
    return orders.filter(order=>(scope==="ALL"||order.status===scope)&&(!normalizedQuery||[order.orderNumber,order.originName,order.destinationName,order.vehicleId||""].some(value=>value.toLowerCase().includes(normalizedQuery))));
  },[orders,query,scope]);
  const visibleOrders=filteredOrders.slice(0,visibleCount);
  const remaining=Math.max(0,filteredOrders.length-visibleOrders.length);

  useEffect(() => {
    setVisibleCount(8);
  }, [scope, query]);

  useEffect(() => {
    setVisibleCount(current => Math.max(8, Math.min(current, Math.max(orders.length, 8))));
  }, [orders.length]);

  return <section className="orderBoard">
    <div className="orderHeader">
      <div><p className="eyebrow">주문 처리</p><h2>주문 → 배송 흐름</h2></div>
      <button disabled={Boolean(busyId)} onClick={onCreate}>+ 새 주문</button>
    </div>
    <div className="orderStats"><span><b>{ready}</b> 배차 대기</span><span><b>{dispatched}</b> 운송 중</span><span><b>{fulfilled}</b> 배송 완료</span><small>등록 주문 {orders.length}건 기준 · 차량 현황은 전체 배송 기준</small></div>
    <div className="orderToolbar">
      <div className="orderScope" aria-label="주문 표시 범위">
        <button type="button" aria-pressed={scope==="ALL"} onClick={()=>setScope("ALL")}>전체 {orders.length}</button>
        <button type="button" aria-pressed={scope==="READY"} onClick={()=>setScope("READY")}>배차 대기 {ready}</button>
        <button type="button" aria-pressed={scope==="DISPATCHED"} onClick={()=>setScope("DISPATCHED")}>운송 중 {dispatched}</button>
        <button type="button" aria-pressed={scope==="FULFILLED"} onClick={()=>setScope("FULFILLED")}>배송 완료 {fulfilled}</button>
      </div>
      <label className="orderSearch" htmlFor="orderSearch"><span>주문 검색</span><input id="orderSearch" type="search" value={query} onChange={event=>setQuery(event.target.value)} placeholder="주문 · 차량 · 지역"/></label>
      {query&&<button type="button" className="orderSearchClear" onClick={()=>setQuery("")}>검색 초기화</button>}
    </div>
    <div className="orderList">
      {orders.length===0?<p className="orderEmpty">새 주문을 만들면 배차 흐름이 여기에 표시됩니다.</p>:filteredOrders.length===0?<p className="orderEmpty">현재 범위와 검색 조건에 맞는 주문이 없습니다.</p>:visibleOrders.map(order=><div className="orderRow" key={order.id}>
        <span className={`orderState ${order.status.toLowerCase()}`}>{orderStatusLabel[order.status]}</span>
        <span className="orderIdentity"><b>{order.orderNumber}</b><small>{order.originName} → {order.destinationName}</small><small><time dateTime={order.createdAt}>접수 {formatOrderTime(order.createdAt)}</time> · <time dateTime={order.updatedAt}>최근 변경 {formatOrderTime(order.updatedAt)}</time></small></span>
        <span className="orderLink">{order.deliveryId?<><b>{order.vehicleId}</b><small>배차 차량</small></>:<><b>미배차</b><small>차량 배차 대기</small></>}</span>
        {order.status==="READY"?<button disabled={Boolean(busyId)} onClick={()=>onDispatch(order.id)} aria-label={`${order.orderNumber} 차량 배차`}>{busyId===order.id?"배차 중…":"차량 배차"}</button>:<span className="orderDeliveryActions"><span className="orderProgress"><i className={(order.deliveryStatus||order.status).toLowerCase()}/>{deliveryStatusLabel[order.deliveryStatus||""]||orderStatusLabel[order.status]}</span>{order.deliveryId&&<button type="button" className="orderFleetLink" onClick={()=>onSelectDelivery(order.deliveryId!)} aria-label={`${order.orderNumber} 배차 차량 현황 보기`}>차량 현황 보기 ↓</button>}</span>}
      </div>)}
      {filteredOrders.length>8?<div className="orderListFooter">
        <span aria-live="polite">주문 {visibleOrders.length} / {filteredOrders.length}건 표시</span>
        {remaining>0?<button type="button" onClick={()=>setVisibleCount(current=>Math.min(current+8,filteredOrders.length))}>다음 {Math.min(8,remaining)}건 보기</button>:<button type="button" onClick={()=>setVisibleCount(8)}>최근 8건만 보기</button>}
      </div>:null}
    </div>
  </section>;
}

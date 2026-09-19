import type { CustomerOrder } from "../types";

type Props = {
  orders: CustomerOrder[];
  busyId?: string;
  onCreate: () => void;
  onDispatch: (id: string) => void;
};

export default function OrderFlowPanel({ orders, busyId, onCreate, onDispatch }: Props) {
  const ready=orders.filter(order=>order.status==="READY").length;
  const dispatched=orders.filter(order=>order.status==="DISPATCHED").length;
  const fulfilled=orders.filter(order=>order.status==="FULFILLED").length;
  return <section className="orderBoard">
    <div className="orderHeader">
      <div><p className="eyebrow">ORDER ORCHESTRATION</p><h2>Order → delivery flow</h2></div>
      <button disabled={Boolean(busyId)} onClick={onCreate}>+ NEW ORDER</button>
    </div>
    <div className="orderStats"><span><b>{ready}</b> READY</span><span><b>{dispatched}</b> DISPATCHED</span><span><b>{fulfilled}</b> FULFILLED</span><small>PostgreSQL order aggregate / linked shipment</small></div>
    <div className="orderList">
      {orders.length===0?<p className="orderEmpty">Create an order to begin the dispatch workflow.</p>:orders.slice(0,8).map(order=><div className="orderRow" key={order.id}>
        <span className={`orderState ${order.status.toLowerCase()}`}>{order.status}</span>
        <span className="orderIdentity"><b>{order.orderNumber}</b><small>{order.originName} → {order.destinationName}</small></span>
        <span className="orderLink">{order.deliveryId?<><b>{order.vehicleId}</b><small>{order.deliveryStatus?.replace("_"," ")}</small></>:<><b>UNASSIGNED</b><small>awaiting vehicle</small></>}</span>
        {order.status==="READY"?<button disabled={Boolean(busyId)} onClick={()=>onDispatch(order.id)}>{busyId===order.id?"DISPATCHING...":"DISPATCH TRUCK"}</button>:<span className="orderProgress"><i className={order.status.toLowerCase()}/>{order.status==="FULFILLED"?"COMPLETE":"IN FLIGHT"}</span>}
      </div>)}
    </div>
  </section>;
}

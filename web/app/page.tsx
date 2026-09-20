"use client";
import { FormEvent, useEffect, useMemo, useRef, useState } from "react";
import dynamic from "next/dynamic";
import DailyKpiPanel from "./components/DailyKpiPanel";
import OrderFlowPanel from "./components/OrderFlowPanel";
import ReplayOperationsPanel from "./components/ReplayOperationsPanel";
import OutboxRecoveryPanel from "./components/OutboxRecoveryPanel";
import AlertOperationsPanel from "./components/AlertOperationsPanel";
import AlertPolicyPanel, { PolicyInput } from "./components/AlertPolicyPanel";
import { fetchJson } from "./api";
import type { AlertPolicy, AlertPolicyAudit, CustomerOrder, DailyDeliveryKpi, DeadLetterEvent, Delivery, DeliveryAlert, LedgerEntry, OutboxFailure, OutboxRetryAudit, ReplayAudit, RouteSnapshot, TelemetryPoint, WarehouseStock, WarehouseTask } from "./types";

const FleetMap=dynamic(()=>import("./components/FleetMap"),{ssr:false});
const API=process.env.NEXT_PUBLIC_API_URL || "http://localhost:8080";

export default function Home(){
 const [items,setItems]=useState<Delivery[]>([]); const [connected,setConnected]=useState(false); const [error,setError]=useState(""); const [selected,setSelected]=useState<string>();
 const knownDeliveryIds=useRef(new Set<string>());
 const requestedMapIds=useRef(new Set<string>());
 const [fleetScope,setFleetScope]=useState<"LIVE"|"ALL">("LIVE"); const [fleetQuery,setFleetQuery]=useState("");
 const [routes,setRoutes]=useState<RouteSnapshot[]>([]);
 const [telemetry,setTelemetry]=useState<TelemetryPoint[]>([]);
 const [alerts,setAlerts]=useState<DeliveryAlert[]>([]);
 const [alertBusy,setAlertBusy]=useState<string>();
 const [policies,setPolicies]=useState<AlertPolicy[]>([]); const [policyAudits,setPolicyAudits]=useState<AlertPolicyAudit[]>([]); const [policyBusy,setPolicyBusy]=useState(false);
 const [orders,setOrders]=useState<CustomerOrder[]>([]); const [orderBusy,setOrderBusy]=useState<string>();
 const [kpis,setKpis]=useState<DailyDeliveryKpi[]>([]);
 const [deadLetters,setDeadLetters]=useState<DeadLetterEvent[]>([]); const [replayAudits,setReplayAudits]=useState<ReplayAudit[]>([]); const [replayBusy,setReplayBusy]=useState<string>();
 const [outboxFailures,setOutboxFailures]=useState<OutboxFailure[]>([]); const [outboxAudits,setOutboxAudits]=useState<OutboxRetryAudit[]>([]); const [outboxBusy,setOutboxBusy]=useState<string>();
 const [stocks,setStocks]=useState<WarehouseStock[]>([]); const [tasks,setTasks]=useState<WarehouseTask[]>([]); const [ledger,setLedger]=useState<LedgerEntry[]>([]); const [warehouseBusy,setWarehouseBusy]=useState(false);
 const loadMapData=async(deliveryIds:string[])=>{
  const ids=[...new Set(deliveryIds)].filter(id=>!requestedMapIds.current.has(id));if(!ids.length)return;
  ids.forEach(id=>requestedMapIds.current.add(id));
  try{const nextRoutes:RouteSnapshot[]=[];const nextTelemetry:TelemetryPoint[]=[];
   for(let offset=0;offset<ids.length;offset+=100){const batch=ids.slice(offset,offset+100);const query=new URLSearchParams({deliveryIds:batch.join(",")});const [r,t]=await Promise.all([fetchJson<RouteSnapshot[]>(`${API}/api/routes?${query}`),fetchJson<TelemetryPoint[]>(`${API}/api/telemetry/points?${query}`)]);nextRoutes.push(...r);nextTelemetry.push(...t)}
   const idSet=new Set(ids);setRoutes(old=>[...nextRoutes,...old.filter(route=>!idSet.has(route.deliveryId))]);setTelemetry(old=>{const merged=new Map([...nextTelemetry,...old].map(point=>[point.eventId,point]));return [...merged.values()].slice(0,5000)})
  }catch(error){ids.forEach(id=>requestedMapIds.current.delete(id));throw error}
 };
 const clearError=(message:string)=>setError(current=>current===message?"":current);
 const load=()=>Promise.all([fetchJson<Delivery[]>(`${API}/api/deliveries`),fetchJson<DeliveryAlert[]>(`${API}/api/alerts`)]).then(async([d,a])=>{knownDeliveryIds.current=new Set(d.map(item=>item.id));setItems(d);setAlerts(a);await loadMapData(d.filter(item=>item.status!=="DELIVERED").map(item=>item.id));clearError("API에 연결할 수 없습니다.")}).catch(()=>setError("API에 연결할 수 없습니다."));
 const loadWarehouse=()=>Promise.all([fetchJson<WarehouseStock[]>(`${API}/api/warehouse/stock`),fetchJson<WarehouseTask[]>(`${API}/api/warehouse/tasks`),fetchJson<LedgerEntry[]>(`${API}/api/warehouse/ledger`)]).then(([s,t,l])=>{setStocks(s);setTasks(t);setLedger(l);clearError("창고 데이터에 연결할 수 없습니다.")}).catch(()=>setError("창고 데이터에 연결할 수 없습니다."));
 const loadKpis=()=>fetchJson<DailyDeliveryKpi[]>(`${API}/api/reports/daily-kpis?days=14`).then(rows=>{setKpis(rows);clearError("KPI 보고서를 불러올 수 없습니다.")}).catch(()=>setError("KPI 보고서를 불러올 수 없습니다."));
 const loadOrders=()=>fetchJson<CustomerOrder[]>(`${API}/api/orders`).then(rows=>{setOrders(rows);clearError("주문 데이터를 불러올 수 없습니다.")}).catch(()=>setError("주문 데이터를 불러올 수 없습니다."));
 const loadReplay=()=>Promise.all([fetchJson<DeadLetterEvent[]>(`${API}/api/operations/dlq`),fetchJson<ReplayAudit[]>(`${API}/api/operations/replay-audits`)]).then(([events,audits])=>{setDeadLetters(events);setReplayAudits(audits);setError(current=>current==="복구 큐를 불러올 수 없습니다."?"":current)}).catch(()=>setError("복구 큐를 불러올 수 없습니다."));
 const loadOutbox=()=>Promise.all([fetchJson<OutboxFailure[]>(`${API}/api/operations/outbox/failures`),fetchJson<OutboxRetryAudit[]>(`${API}/api/operations/outbox/retry-audits`)]).then(([failures,audits])=>{setOutboxFailures(failures);setOutboxAudits(audits);clearError("Outbox 복구 큐를 불러올 수 없습니다.")}).catch(()=>setError("Outbox 복구 큐를 불러올 수 없습니다."));
 const loadPolicies=()=>Promise.all([fetchJson<AlertPolicy[]>(`${API}/api/alert-policies`),fetchJson<AlertPolicyAudit[]>(`${API}/api/alert-policies/audits`)]).then(([nextPolicies,nextAudits])=>{setPolicies(nextPolicies);setPolicyAudits(nextAudits);clearError("경고 정책을 불러올 수 없습니다.")}).catch(()=>setError("경고 정책을 불러올 수 없습니다."));
 useEffect(()=>{load(); const source=new EventSource(`${API}/api/stream/deliveries`); source.onopen=()=>setConnected(true); source.onerror=()=>setConnected(false);
  source.addEventListener("delivery-update",e=>{const next:Delivery=JSON.parse((e as MessageEvent).data);if(!knownDeliveryIds.current.has(next.id)){knownDeliveryIds.current.add(next.id);loadMapData([next.id]).catch(()=>{})}setItems(old=>[next,...old.filter(x=>x.id!==next.id)]);loadOrders().catch(()=>{})});
  source.addEventListener("telemetry-point",e=>{const next:TelemetryPoint=JSON.parse((e as MessageEvent).data);setTelemetry(old=>old.some(point=>point.eventId===next.eventId)?old:[next,...old].slice(0,5000))});
  source.addEventListener("alert-update",e=>{const next:DeliveryAlert=JSON.parse((e as MessageEvent).data);setAlerts(old=>[next,...old.filter(x=>x.id!==next.id)])});return()=>source.close()},[]);
 const liveItems=useMemo(()=>items.filter(item=>item.status!=="DELIVERED"),[items]);
 const scopedItems=fleetScope==="LIVE"?liveItems:items;
 const visibleItems=useMemo(()=>{const query=fleetQuery.trim().toLowerCase();return query?scopedItems.filter(item=>[item.vehicleId,item.orderNumber,item.originName,item.destinationName].some(value=>value.toLowerCase().includes(query))):scopedItems},[scopedItems,fleetQuery]);
 useEffect(()=>{if(visibleItems.length&&!visibleItems.some(item=>item.id===selected))setSelected(visibleItems.find(item=>routes.some(route=>route.deliveryId===item.id))?.id||visibleItems[0].id)},[visibleItems,routes,selected]);
 useEffect(()=>{loadMapData(scopedItems.map(item=>item.id)).catch(()=>setError("지도 경로를 불러올 수 없습니다."))},[fleetScope,items]);
 function focusDelivery(id:string){if(items.find(item=>item.id===id)?.status==="DELIVERED")setFleetScope("ALL");setFleetQuery("");setSelected(id)}
 useEffect(()=>{loadWarehouse()},[]);
 useEffect(()=>pollAfterCompletion(loadOrders,15000),[]);
 useEffect(()=>pollAfterCompletion(loadKpis,30000),[]);
 useEffect(()=>pollAfterCompletion(loadReplay,15000),[]);
 useEffect(()=>pollAfterCompletion(loadOutbox,15000),[]);
 useEffect(()=>pollAfterCompletion(loadPolicies,30000),[]);
 async function createOrder(e?:FormEvent){e?.preventDefault();setOrderBusy("create");setError("");try{const suffix=Date.now().toString().slice(-6);const response=await fetch(`${API}/api/orders`,{method:"POST",headers:{"Content-Type":"application/json","Idempotency-Key":crypto.randomUUID()},body:JSON.stringify({orderNumber:`ORD-${suffix}`,origin:{name:"Seoul Hub",lat:37.5665,lon:126.978},destination:{name:"Incheon DC",lat:37.4563,lon:126.7052}})});if(!response.ok)throw new Error();await loadOrders()}catch{setError("주문 생성에 실패했습니다.")}finally{setOrderBusy(undefined)}}
 async function dispatchOrder(id:string){setOrderBusy(id);setError("");try{const response=await fetch(`${API}/api/orders/${id}/dispatch`,{method:"POST",headers:{"Content-Type":"application/json","Idempotency-Key":crypto.randomUUID()},body:JSON.stringify({vehicleId:`TRUCK-${Math.ceil(Math.random()*9).toString().padStart(2,"0")}`})});if(!response.ok)throw new Error();const order:CustomerOrder=await response.json();if(order.deliveryId)setSelected(order.deliveryId);await Promise.all([loadOrders(),load()])}catch{setError("주문 배차에 실패했습니다.")}finally{setOrderBusy(undefined)}}
 async function receiveStock(){setWarehouseBusy(true);setError("");try{const suffix=Date.now().toString().slice(-6);const r=await fetch(`${API}/api/warehouse/receipts`,{method:"POST",headers:{"Content-Type":"application/json","Idempotency-Key":crypto.randomUUID()},body:JSON.stringify({referenceNumber:`ASN-${suffix}`,warehouseId:"SEOUL-HUB-A",sku:"COLD-BOX-01",quantity:10})});if(!r.ok)throw new Error();await loadWarehouse()}catch{setError("입고 처리에 실패했습니다.")}finally{setWarehouseBusy(false)}}
 async function pickAndDispatch(){setWarehouseBusy(true);setError("");try{const suffix=Date.now().toString().slice(-6);const pick=await fetch(`${API}/api/warehouse/outbounds`,{method:"POST",headers:{"Content-Type":"application/json","Idempotency-Key":crypto.randomUUID()},body:JSON.stringify({referenceNumber:`OUT-${suffix}`,warehouseId:"SEOUL-HUB-A",sku:"COLD-BOX-01",quantity:4})});if(!pick.ok)throw new Error();const task:WarehouseTask=await pick.json();const dispatched=await fetch(`${API}/api/warehouse/outbounds/${task.id}/dispatch`,{method:"POST"});if(!dispatched.ok)throw new Error();await loadWarehouse()}catch{setError("출고 처리에 실패했습니다. 먼저 재고를 입고해 주세요.")}finally{setWarehouseBusy(false)}}
 async function replay(id:string){setReplayBusy(id);setError("");try{const response=await fetch(`${API}/api/operations/dlq/${id}/replay`,{method:"POST",headers:{"X-Operator":"control-tower"}});if(!response.ok)throw new Error();await loadReplay()}catch{setError("DLQ 이벤트 재처리에 실패했습니다.")}finally{setReplayBusy(undefined)}}
 async function discard(id:string){const reason=window.prompt("폐기 사유를 입력하세요 (필수, 최대 500자).");if(reason===null)return;setReplayBusy(id);setError("");try{const response=await fetch(`${API}/api/operations/dlq/${id}/discard`,{method:"POST",headers:{"Content-Type":"application/json","X-Operator":"control-tower"},body:JSON.stringify({reason})});if(!response.ok)throw new Error();await loadReplay()}catch{setError("DLQ 이벤트 폐기에 실패했습니다. 폐기 사유를 확인해 주세요.")}finally{setReplayBusy(undefined)}}
 async function retryOutbox(id:string){setOutboxBusy(id);setError("");try{const response=await fetch(`${API}/api/operations/outbox/failures/${id}/retry`,{method:"POST",headers:{"X-Operator":"control-tower"}});if(!response.ok)throw new Error();await loadOutbox()}catch{setError("Outbox 이벤트 재발행에 실패했습니다.")}finally{setOutboxBusy(undefined)}}
 async function acknowledgeAlert(id:string){setAlertBusy(id);setError("");try{const response=await fetch(`${API}/api/alerts/${id}/acknowledgement`,{method:"POST",headers:{"X-Operator":"control-tower","X-Trace-Id":crypto.randomUUID()}});if(!response.ok)throw new Error();const next:DeliveryAlert=await response.json();setAlerts(old=>[next,...old.filter(alert=>alert.id!==next.id)])}catch{setError("경고 확인 처리에 실패했습니다.")}finally{setAlertBusy(undefined)}}
 async function savePolicy(policy:PolicyInput){setPolicyBusy(true);setError("");try{const response=await fetch(`${API}/api/alert-policies`,{method:"POST",headers:{"Content-Type":"application/json","X-Operator":"control-tower"},body:JSON.stringify(policy)});if(!response.ok)throw new Error();await loadPolicies()}catch{setError("경고 정책 저장에 실패했습니다. CLOSE < OPEN ≤ CRITICAL 순서를 확인해 주세요.")}finally{setPolicyBusy(false)}}
 async function resetPolicy(vehicleId:string){setPolicyBusy(true);setError("");try{const response=await fetch(`${API}/api/alert-policies/${encodeURIComponent(vehicleId)}`,{method:"DELETE",headers:{"X-Operator":"control-tower"}});if(!response.ok)throw new Error();await loadPolicies()}catch{setError("차량 정책을 전역 기본값으로 되돌리지 못했습니다.")}finally{setPolicyBusy(false)}}
 async function restorePolicy(auditId:string){setPolicyBusy(true);setError("");try{const response=await fetch(`${API}/api/alert-policies/audits/${auditId}/restore`,{method:"POST",headers:{"X-Operator":"control-tower"}});if(!response.ok)throw new Error();await loadPolicies()}catch{setError("감사 이력에서 경고 정책을 복원하지 못했습니다.")}finally{setPolicyBusy(false)}}
 const focus=items.find(x=>x.id===selected);
 const focusRoute=routes.find(x=>x.deliveryId===selected);
 const activeAlerts=alerts.filter(alert=>alert.status==="ACTIVE");
 return <main><header><div><p className="eyebrow">OPERATIONS / LIVE</p><h1>LogiTrack Control Tower</h1></div><div className={`signal ${connected?"on":""}`}><i/>{connected?"LIVE STREAM":"RECONNECTING"}</div></header>
  <section className="hero"><div><span>ACTIVE DELIVERIES</span><strong>{items.filter(x=>x.status!=="DELIVERED").length.toString().padStart(2,"0")}</strong></div><div><span>ACTIVE ALERTS</span><strong className={activeAlerts.length?"alertCount":""}>{activeAlerts.length.toString().padStart(2,"0")}</strong></div><div><span>FLEET PROGRESS</span><strong>{items.length?Math.round(items.reduce((n,x)=>n+x.progress,0)/items.length*100):0}%</strong></div><form onSubmit={createOrder}><button disabled={Boolean(orderBusy)}>+ CREATE ORDER</button></form></section>
  {error&&<p className="error">{error}</p>}
  <OrderFlowPanel orders={orders} busyId={orderBusy} onCreate={()=>createOrder()} onDispatch={dispatchOrder}/>
  <DailyKpiPanel rows={kpis} csvUrl={`${API}/api/reports/daily-kpis.csv?days=30`} pdfUrl={`${API}/api/reports/daily-kpis.pdf?days=30`}/>
  <section className="mapBoard"><div className="mapHeader"><div className="mapTitle"><p className="eyebrow">GEOSPATIAL OVERVIEW</p><h2>Live fleet map</h2><div className="mapControls"><div className="mapScope" aria-label="Fleet scope"><button type="button" aria-pressed={fleetScope==="LIVE"} className={fleetScope==="LIVE"?"active":""} onClick={()=>setFleetScope("LIVE")}>LIVE {liveItems.length}</button><button type="button" aria-pressed={fleetScope==="ALL"} className={fleetScope==="ALL"?"active":""} onClick={()=>setFleetScope("ALL")}>ALL {items.length}</button></div><label className="mapSearch" htmlFor="fleetSearch"><span>FIND</span><input id="fleetSearch" type="search" value={fleetQuery} onChange={event=>setFleetQuery(event.target.value)} placeholder="vehicle, order or place"/></label></div></div>{focus&&visibleItems.some(item=>item.id===focus.id)&&<div className="focusStats"><span><small>FOCUS</small>{focus.vehicleId}</span><span><small>PROGRESS</small>{Math.round(focus.progress*100)}%</span><span><small>ROUTE</small>{focusRoute?`${(focusRoute.distanceMeters/1000).toFixed(1)} km · ${focusRoute.provider.toUpperCase()}`:"CALCULATING"}</span><span><small>ETA</small>{focus.eta?new Date(focus.eta).toLocaleTimeString("ko-KR",{hour:"2-digit",minute:"2-digit"}):focus.status==="DELIVERED"?"ARRIVED":focusRoute?new Date(focusRoute.plannedEta).toLocaleTimeString("ko-KR",{hour:"2-digit",minute:"2-digit"}):"—"}</span></div>}</div>
   <FleetMap deliveries={visibleItems} routes={routes} telemetry={telemetry} selectedId={selected} onSelect={setSelected} emptyMessage={fleetQuery?`“${fleetQuery}” 검색 결과가 없습니다. 검색어를 지우거나 범위를 전환해 주세요.`:undefined}/></section>
  <AlertOperationsPanel alerts={alerts} deliveries={items} busyId={alertBusy} onSelect={focusDelivery} onAcknowledge={acknowledgeAlert}/>
  <AlertPolicyPanel policies={policies} audits={policyAudits} deliveries={items} busy={policyBusy} onSave={savePolicy} onReset={resetPolicy} onRestore={restorePolicy}/>
  <section className="board"><div className="boardTitle"><h2>Fleet telemetry</h2><span>{visibleItems.length} shown · {items.length} total · {fleetScope} scope</span></div>
  <div className="grid">{visibleItems.length===0?<div className="empty">{items.length===0?"배송을 생성하면 차량 위치 이벤트가 지도와 목록에 표시됩니다.":"현재 범위와 검색 조건에 맞는 배송이 없습니다."}</div>:visibleItems.map(d=>{const count=activeAlerts.filter(alert=>alert.deliveryId===d.id).length;return <article key={d.id} onClick={()=>focusDelivery(d.id)} className={selected===d.id?"selected":""}><div className="row"><span className={`badge ${d.status.toLowerCase()}`}>{d.status.replace("_"," ")}</span><b>{count>0&&<i className="cardAlert">{count}</i>}{d.vehicleId}</b></div><h3>{d.orderNumber}</h3><p>{d.originName} <em>→</em> {d.destinationName}</p><div className="track"><i style={{width:`${d.progress*100}%`}}/></div><div className="meta"><span>{Math.round(d.progress*100)}% complete</span><span>{d.currentLat?.toFixed(4)}, {d.currentLon?.toFixed(4)}</span></div></article>})}</div></section>
  <section className="warehouseBoard"><div className="warehouseHeader"><div><p className="eyebrow">WAREHOUSE / INVENTORY</p><h2>Stock control</h2></div><div className="warehouseActions"><button disabled={warehouseBusy} onClick={receiveStock}>+ RECEIVE 10</button><button disabled={warehouseBusy} onClick={pickAndDispatch}>PICK & DISPATCH 4</button></div></div>
   <div className="warehouseGrid"><div className="stockPane"><h4>AVAILABLE STOCK</h4>{stocks.length===0?<p className="warehouseEmpty">No inventory yet. Receive demo stock to begin.</p>:<div className="stockTable"><div className="stockRow head"><span>LOCATION / SKU</span><span>ON HAND</span><span>RESERVED</span><span>AVAILABLE</span></div>{stocks.slice(0,8).map(s=><div className="stockRow" key={s.id}><span><b>{s.warehouseId}</b><small>{s.sku}</small></span><strong>{s.onHand}</strong><strong>{s.reserved}</strong><strong className="available">{s.available}</strong></div>)}</div>}</div>
   <div className="ledgerPane"><h4>RECENT LEDGER</h4>{ledger.length===0?<p className="warehouseEmpty">Inventory movements will appear here.</p>:ledger.slice(0,7).map(e=><div className="ledgerRow" key={e.id}><span className={`movement ${e.transactionType.toLowerCase()}`}>{e.transactionType}</span><span><b>{e.sku}</b><small>{e.warehouseId}</small></span><span className="delta">{e.onHandDelta>0?`+${e.onHandDelta}`:e.onHandDelta||`R +${e.reservedDelta}`}</span></div>)}</div></div>
   <div className="taskStrip"><span>{tasks.filter(t=>t.status==="PICKED").length} awaiting dispatch</span><span>{tasks.filter(t=>t.status==="DISPATCHED").length} dispatched</span><span>{ledger.length} ledger movements loaded</span></div>
  </section>
  <ReplayOperationsPanel events={deadLetters} audits={replayAudits} busyId={replayBusy} onReplay={replay} onDiscard={discard}/>
  <OutboxRecoveryPanel failures={outboxFailures} audits={outboxAudits} busyId={outboxBusy} onRetry={retryOutbox}/>
 </main>
}

function pollAfterCompletion(task:()=>Promise<unknown>,delayMs:number){
 let stopped=false;let timer:number|undefined;
 const poll=async()=>{try{await task()}catch{}finally{if(!stopped)timer=window.setTimeout(poll,delayMs)}};
 void poll();
 return()=>{stopped=true;if(timer!==undefined)window.clearTimeout(timer)};
}

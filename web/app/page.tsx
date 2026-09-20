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
import type { AlertPolicy, AlertPolicyAudit, CustomerOrder, DailyDeliveryKpi, DeadLetterEvent, DeadLetterPage, Delivery, DeliveryAlert, DiscardPlan, LedgerEntry, OutboxFailure, OutboxRetryAudit, ReplayAudit, RouteSnapshot, TelemetryPoint, WarehouseStock, WarehouseTask } from "./types";

const FleetMap=dynamic(()=>import("./components/FleetMap"),{ssr:false});
const API=process.env.NEXT_PUBLIC_API_URL || "http://localhost:8080";
type Workspace="overview"|"orders"|"warehouse"|"recovery"|"settings";
const workspaceCopy:Record<Workspace,{label:string;eyebrow:string;title:string;description:string}>={
 overview:{label:"Overview",eyebrow:"CONTROL TOWER",title:"오늘의 운송 상황",description:"지도에서 차량 흐름과 예외 상황을 한눈에 확인하세요."},
 orders:{label:"Orders & Fleet",eyebrow:"ORDER OPERATIONS",title:"주문과 차량",description:"주문 생성부터 배차, 차량별 상세 진행률까지 관리합니다."},
 warehouse:{label:"Warehouse",eyebrow:"WAREHOUSE OPERATIONS",title:"창고와 재고",description:"가용 재고, 입출고 작업과 최근 원장 흐름을 확인합니다."},
 recovery:{label:"Recovery",eyebrow:"SYSTEM RECOVERY",title:"복구 작업",description:"처리에 실패한 이벤트를 검토하고 안전하게 복구합니다."},
 settings:{label:"Alert Policies",eyebrow:"POLICY MANAGEMENT",title:"경고 정책",description:"차량별 임계값과 정책 변경 이력을 관리합니다."}
};
const workspaceKeys=Object.keys(workspaceCopy) as Workspace[];
function workspaceFromHash(hash:string):Workspace|undefined{const value=hash.replace(/^#/,"");return workspaceKeys.includes(value as Workspace)?value as Workspace:undefined}

export default function Home(){
 const [workspace,setWorkspace]=useState<Workspace>("overview");
 const [workspaceReady,setWorkspaceReady]=useState(false);
 const [loadedWorkspaces,setLoadedWorkspaces]=useState<Set<Workspace>>(()=>new Set(["overview"]));
 const workspaceRef=useRef<Workspace>("overview");
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
 const [deadLetters,setDeadLetters]=useState<DeadLetterEvent[]>([]); const [deadLetterTotal,setDeadLetterTotal]=useState(0); const [replayAudits,setReplayAudits]=useState<ReplayAudit[]>([]); const [replayBusy,setReplayBusy]=useState<string>(); const [replayPageBusy,setReplayPageBusy]=useState(false); const replayLastPage=useRef(0);
 const [discardPlan,setDiscardPlan]=useState<DiscardPlan>(); const [discardPlanBusy,setDiscardPlanBusy]=useState(false);
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
 const load=()=>Promise.all([fetchJson<Delivery[]>(`${API}/api/deliveries`),fetchJson<DeliveryAlert[]>(`${API}/api/alerts`)]).then(async([d,a])=>{knownDeliveryIds.current=new Set(d.map(item=>item.id));setItems(d);setAlerts(a);if(workspaceRef.current==="overview"||workspaceRef.current==="orders")await loadMapData(d.filter(item=>item.status!=="DELIVERED").map(item=>item.id));clearError("API에 연결할 수 없습니다.")}).catch(()=>setError("API에 연결할 수 없습니다."));
 const loadWarehouse=()=>Promise.all([fetchJson<WarehouseStock[]>(`${API}/api/warehouse/stock`),fetchJson<WarehouseTask[]>(`${API}/api/warehouse/tasks`),fetchJson<LedgerEntry[]>(`${API}/api/warehouse/ledger`)]).then(([s,t,l])=>{setStocks(s);setTasks(t);setLedger(l);clearError("창고 데이터에 연결할 수 없습니다.")}).catch(()=>setError("창고 데이터에 연결할 수 없습니다."));
 const loadKpis=()=>fetchJson<DailyDeliveryKpi[]>(`${API}/api/reports/daily-kpis?days=14`).then(rows=>{setKpis(rows);clearError("KPI 보고서를 불러올 수 없습니다.")}).catch(()=>setError("KPI 보고서를 불러올 수 없습니다."));
 const loadOrders=()=>fetchJson<CustomerOrder[]>(`${API}/api/orders`).then(rows=>{setOrders(rows);clearError("주문 데이터를 불러올 수 없습니다.")}).catch(()=>setError("주문 데이터를 불러올 수 없습니다."));
 const loadReplay=()=>Promise.all([Promise.all(Array.from({length:replayLastPage.current+1},(_,page)=>fetchJson<DeadLetterPage>(`${API}/api/operations/dlq-page?status=PENDING&page=${page}&size=100`))),fetchJson<ReplayAudit[]>(`${API}/api/operations/replay-audits`)]).then(([pages,audits])=>{const merged=new Map(pages.flatMap(page=>page.items).map(event=>[event.id,event]));setDeadLetters([...merged.values()]);setDeadLetterTotal(pages[0]?.totalElements||0);setReplayAudits(audits);setError(current=>current==="복구 큐를 불러올 수 없습니다."?"":current)}).catch(()=>setError("복구 큐를 불러올 수 없습니다."));
 const loadReplayCount=()=>fetchJson<DeadLetterPage>(`${API}/api/operations/dlq-page?status=PENDING&page=0&size=1`).then(page=>setDeadLetterTotal(page.totalElements)).catch(()=>{});
 const loadMoreReplay=async()=>{setReplayPageBusy(true);try{const next=replayLastPage.current+1;const page=await fetchJson<DeadLetterPage>(`${API}/api/operations/dlq-page?status=PENDING&page=${next}&size=100`);replayLastPage.current=next;setDeadLetters(current=>{const merged=new Map([...current,...page.items].map(event=>[event.id,event]));return [...merged.values()]});setDeadLetterTotal(page.totalElements);clearError("복구 큐를 불러올 수 없습니다.")}catch{setError("복구 큐를 불러올 수 없습니다.")}finally{setReplayPageBusy(false)}};
 const loadOutbox=()=>Promise.all([fetchJson<OutboxFailure[]>(`${API}/api/operations/outbox/failures`),fetchJson<OutboxRetryAudit[]>(`${API}/api/operations/outbox/retry-audits`)]).then(([failures,audits])=>{setOutboxFailures(failures);setOutboxAudits(audits);clearError("Outbox 복구 큐를 불러올 수 없습니다.")}).catch(()=>setError("Outbox 복구 큐를 불러올 수 없습니다."));
 const loadPolicies=()=>Promise.all([fetchJson<AlertPolicy[]>(`${API}/api/alert-policies`),fetchJson<AlertPolicyAudit[]>(`${API}/api/alert-policies/audits`)]).then(([nextPolicies,nextAudits])=>{setPolicies(nextPolicies);setPolicyAudits(nextAudits);clearError("경고 정책을 불러올 수 없습니다.")}).catch(()=>setError("경고 정책을 불러올 수 없습니다."));
 const markLoaded=(key:Workspace)=>setLoadedWorkspaces(current=>current.has(key)?current:new Set([...current,key]));
 const loadOrderWorkspace=()=>loadOrders().finally(()=>markLoaded("orders"));
 const loadWarehouseWorkspace=()=>loadWarehouse().finally(()=>markLoaded("warehouse"));
 const loadRecoveryWorkspace=()=>Promise.all([loadReplay(),loadOutbox()]).finally(()=>markLoaded("recovery"));
 const loadPolicyWorkspace=()=>loadPolicies().finally(()=>markLoaded("settings"));
 useEffect(()=>{const sync=()=>{const next=workspaceFromHash(window.location.hash);if(next){workspaceRef.current=next;setWorkspace(next)}};sync();if(!window.location.hash)window.history.replaceState(null,"",`${window.location.pathname}${window.location.search}#overview`);setWorkspaceReady(true);window.addEventListener("popstate",sync);window.addEventListener("hashchange",sync);return()=>{window.removeEventListener("popstate",sync);window.removeEventListener("hashchange",sync)}},[]);
 useEffect(()=>{if(!workspaceReady)return;load(); const source=new EventSource(`${API}/api/stream/deliveries`); source.onopen=()=>setConnected(true); source.onerror=()=>setConnected(false);
  source.addEventListener("delivery-update",e=>{const next:Delivery=JSON.parse((e as MessageEvent).data);if(!knownDeliveryIds.current.has(next.id)){knownDeliveryIds.current.add(next.id);if(workspaceRef.current==="overview"||workspaceRef.current==="orders")loadMapData([next.id]).catch(()=>{})}setItems(old=>[next,...old.filter(x=>x.id!==next.id)])});
  source.addEventListener("telemetry-point",e=>{const next:TelemetryPoint=JSON.parse((e as MessageEvent).data);setTelemetry(old=>old.some(point=>point.eventId===next.eventId)?old:[next,...old].slice(0,5000))});
  source.addEventListener("alert-update",e=>{const next:DeliveryAlert=JSON.parse((e as MessageEvent).data);setAlerts(old=>[next,...old.filter(x=>x.id!==next.id)])});return()=>source.close()},[workspaceReady]);
 const liveItems=useMemo(()=>items.filter(item=>item.status!=="DELIVERED"),[items]);
 const scopedItems=fleetScope==="LIVE"?liveItems:items;
 const visibleItems=useMemo(()=>{const query=fleetQuery.trim().toLowerCase();return query?scopedItems.filter(item=>[item.vehicleId,item.orderNumber,item.originName,item.destinationName].some(value=>value.toLowerCase().includes(query))):scopedItems},[scopedItems,fleetQuery]);
 useEffect(()=>{if(visibleItems.length&&!visibleItems.some(item=>item.id===selected))setSelected(visibleItems.find(item=>routes.some(route=>route.deliveryId===item.id))?.id||visibleItems[0].id)},[visibleItems,routes,selected]);
 useEffect(()=>{workspaceRef.current=workspace},[workspace]);
 useEffect(()=>{if(workspace==="overview"||workspace==="orders")loadMapData(scopedItems.map(item=>item.id)).catch(()=>setError("지도 경로를 불러올 수 없습니다."))},[fleetScope,items,workspace]);
 function focusDelivery(id:string){if(items.find(item=>item.id===id)?.status==="DELIVERED")setFleetScope("ALL");setFleetQuery("");setSelected(id)}
 useEffect(()=>workspaceReady&&workspace==="warehouse"?pollAfterCompletion(loadWarehouseWorkspace,30000):undefined,[workspaceReady,workspace]);
 useEffect(()=>workspaceReady&&workspace==="orders"?pollAfterCompletion(loadOrderWorkspace,15000):undefined,[workspaceReady,workspace]);
 useEffect(()=>workspaceReady&&workspace==="overview"?pollAfterCompletion(loadKpis,30000):undefined,[workspaceReady,workspace]);
 useEffect(()=>workspaceReady?(workspace==="recovery"?pollAfterCompletion(loadRecoveryWorkspace,15000):pollAfterCompletion(loadReplayCount,30000)):undefined,[workspaceReady,workspace]);
 useEffect(()=>workspaceReady&&workspace==="settings"?pollAfterCompletion(loadPolicyWorkspace,30000):undefined,[workspaceReady,workspace]);
 async function createOrder(e?:FormEvent){e?.preventDefault();setOrderBusy("create");setError("");try{const suffix=Date.now().toString().slice(-6);const response=await fetch(`${API}/api/orders`,{method:"POST",headers:{"Content-Type":"application/json","Idempotency-Key":crypto.randomUUID()},body:JSON.stringify({orderNumber:`ORD-${suffix}`,origin:{name:"Seoul Hub",lat:37.5665,lon:126.978},destination:{name:"Incheon DC",lat:37.4563,lon:126.7052}})});if(!response.ok)throw new Error();await loadOrders()}catch{setError("주문 생성에 실패했습니다.")}finally{setOrderBusy(undefined)}}
 async function dispatchOrder(id:string){setOrderBusy(id);setError("");try{const response=await fetch(`${API}/api/orders/${id}/dispatch`,{method:"POST",headers:{"Content-Type":"application/json","Idempotency-Key":crypto.randomUUID()},body:JSON.stringify({vehicleId:`TRUCK-${Math.ceil(Math.random()*9).toString().padStart(2,"0")}`})});if(!response.ok)throw new Error();const order:CustomerOrder=await response.json();if(order.deliveryId)setSelected(order.deliveryId);await Promise.all([loadOrders(),load()])}catch{setError("주문 배차에 실패했습니다.")}finally{setOrderBusy(undefined)}}
 async function receiveStock(){setWarehouseBusy(true);setError("");try{const suffix=Date.now().toString().slice(-6);const r=await fetch(`${API}/api/warehouse/receipts`,{method:"POST",headers:{"Content-Type":"application/json","Idempotency-Key":crypto.randomUUID()},body:JSON.stringify({referenceNumber:`ASN-${suffix}`,warehouseId:"SEOUL-HUB-A",sku:"COLD-BOX-01",quantity:10})});if(!r.ok)throw new Error();await loadWarehouse()}catch{setError("입고 처리에 실패했습니다.")}finally{setWarehouseBusy(false)}}
 async function pickAndDispatch(){setWarehouseBusy(true);setError("");try{const suffix=Date.now().toString().slice(-6);const pick=await fetch(`${API}/api/warehouse/outbounds`,{method:"POST",headers:{"Content-Type":"application/json","Idempotency-Key":crypto.randomUUID()},body:JSON.stringify({referenceNumber:`OUT-${suffix}`,warehouseId:"SEOUL-HUB-A",sku:"COLD-BOX-01",quantity:4})});if(!pick.ok)throw new Error();const task:WarehouseTask=await pick.json();const dispatched=await fetch(`${API}/api/warehouse/outbounds/${task.id}/dispatch`,{method:"POST"});if(!dispatched.ok)throw new Error();await loadWarehouse()}catch{setError("출고 처리에 실패했습니다. 먼저 재고를 입고해 주세요.")}finally{setWarehouseBusy(false)}}
 async function replay(id:string){setReplayBusy(id);setError("");try{const response=await fetch(`${API}/api/operations/dlq/${id}/replay`,{method:"POST",headers:{"X-Operator":"control-tower"}});if(!response.ok)throw new Error();await loadReplay()}catch{setError("DLQ 이벤트 재처리에 실패했습니다.")}finally{setReplayBusy(undefined)}}
 async function discard(id:string){const reason=window.prompt("폐기 사유를 입력하세요 (필수, 최대 500자).");if(reason===null)return;setReplayBusy(id);setError("");try{const response=await fetch(`${API}/api/operations/dlq/${id}/discard`,{method:"POST",headers:{"Content-Type":"application/json","X-Operator":"control-tower"},body:JSON.stringify({reason})});if(!response.ok)throw new Error();await loadReplay()}catch{setError("DLQ 이벤트 폐기에 실패했습니다. 폐기 사유를 확인해 주세요.")}finally{setReplayBusy(undefined)}}
 async function prepareDiscard(ids:string[],reason:string){setDiscardPlanBusy(true);setError("");try{const response=await fetch(`${API}/api/operations/discard-plans`,{method:"POST",headers:{"Content-Type":"application/json","X-Operator":"control-tower"},body:JSON.stringify({eventIds:ids,reason})});if(!response.ok)throw new Error();setDiscardPlan(await response.json())}catch{setError("일괄 폐기 계획 생성에 실패했습니다. 선택 항목과 사유를 확인해 주세요.")}finally{setDiscardPlanBusy(false)}}
 async function executeDiscard(id:string){setDiscardPlanBusy(true);setError("");try{const response=await fetch(`${API}/api/operations/discard-plans/${id}/execute`,{method:"POST",headers:{"X-Operator":"control-tower","X-Discard-Approval":"DISCARD"}});if(!response.ok)throw new Error();setDiscardPlan(await response.json());await loadReplay()}catch{setError("일괄 폐기 실행에 실패했습니다. 계획 만료 또는 이벤트 상태를 확인해 주세요.")}finally{setDiscardPlanBusy(false)}}
 async function retryOutbox(id:string){setOutboxBusy(id);setError("");try{const response=await fetch(`${API}/api/operations/outbox/failures/${id}/retry`,{method:"POST",headers:{"X-Operator":"control-tower"}});if(!response.ok)throw new Error();await loadOutbox()}catch{setError("Outbox 이벤트 재발행에 실패했습니다.")}finally{setOutboxBusy(undefined)}}
 async function acknowledgeAlert(id:string){setAlertBusy(id);setError("");try{const response=await fetch(`${API}/api/alerts/${id}/acknowledgement`,{method:"POST",headers:{"X-Operator":"control-tower","X-Trace-Id":crypto.randomUUID()}});if(!response.ok)throw new Error();const next:DeliveryAlert=await response.json();setAlerts(old=>[next,...old.filter(alert=>alert.id!==next.id)])}catch{setError("경고 확인 처리에 실패했습니다.")}finally{setAlertBusy(undefined)}}
 async function savePolicy(policy:PolicyInput){setPolicyBusy(true);setError("");try{const response=await fetch(`${API}/api/alert-policies`,{method:"POST",headers:{"Content-Type":"application/json","X-Operator":"control-tower"},body:JSON.stringify(policy)});if(!response.ok)throw new Error();await loadPolicies()}catch{setError("경고 정책 저장에 실패했습니다. CLOSE < OPEN ≤ CRITICAL 순서를 확인해 주세요.")}finally{setPolicyBusy(false)}}
 async function resetPolicy(vehicleId:string){setPolicyBusy(true);setError("");try{const response=await fetch(`${API}/api/alert-policies/${encodeURIComponent(vehicleId)}`,{method:"DELETE",headers:{"X-Operator":"control-tower"}});if(!response.ok)throw new Error();await loadPolicies()}catch{setError("차량 정책을 전역 기본값으로 되돌리지 못했습니다.")}finally{setPolicyBusy(false)}}
 async function restorePolicy(auditId:string){setPolicyBusy(true);setError("");try{const response=await fetch(`${API}/api/alert-policies/audits/${auditId}/restore`,{method:"POST",headers:{"X-Operator":"control-tower"}});if(!response.ok)throw new Error();await loadPolicies()}catch{setError("감사 이력에서 경고 정책을 복원하지 못했습니다.")}finally{setPolicyBusy(false)}}
 const focus=items.find(x=>x.id===selected);
 const focusRoute=routes.find(x=>x.deliveryId===selected);
 const activeAlerts=alerts.filter(alert=>alert.status==="ACTIVE");
 function openWorkspace(next:Workspace){setWorkspace(next);if(workspaceFromHash(window.location.hash)!==next)window.history.pushState(null,"",`${window.location.pathname}${window.location.search}#${next}`)}
 const copy=workspaceCopy[workspace];
 return <main><a className="skipLink" href="#workspace-content" onClick={event=>{event.preventDefault();const content=document.getElementById("workspace-content");content?.focus();content?.scrollIntoView()}}>본문 바로가기</a><header className="appHeader"><button className="brand" type="button" onClick={()=>openWorkspace("overview")} aria-label="LogiTrack 상황판으로 이동"><span>LT</span><div><p className="eyebrow">OPERATIONS / LIVE</p><h1>LogiTrack</h1></div></button><div className="headerStatus"><span className={`signal ${connected?"on":""}`} aria-live="polite"><i/>{connected?"LIVE STREAM":"RECONNECTING"}</span><small>CONTROL TOWER</small></div></header>
  <nav className="workspaceNav" aria-label="Control tower workspaces">
   {workspaceKeys.map(key=><a key={key} href={`#${key}`} aria-current={workspace===key?"page":undefined} onClick={event=>{event.preventDefault();openWorkspace(key)}}><span>{workspaceCopy[key].label}</span>{key==="overview"&&activeAlerts.length>0&&<b aria-label={`${activeAlerts.length} active alerts`}>{activeAlerts.length}</b>}{key==="recovery"&&deadLetterTotal>0&&<b aria-label={`${deadLetterTotal} pending recovery events`}>{deadLetterTotal}</b>}</a>)}
  </nav>
  <div id="workspace-content" className="workspaceContent" tabIndex={-1}><section className="workspaceIntro"><div><p className="eyebrow">{copy.eyebrow}</p><h2>{copy.title}</h2><p>{copy.description}</p></div>{workspace!=="overview"&&<button type="button" onClick={()=>openWorkspace("overview")}>← 상황판으로</button>}</section>
  {error&&<p className="error">{error}</p>}
  {!loadedWorkspaces.has(workspace)?<WorkspaceLoading label={copy.label}/>:<>
  {workspace==="overview"&&<><section className="hero"><div><span>운송 중</span><strong>{liveItems.length.toString().padStart(2,"0")}</strong><small>전체 {items.length}건</small></div><div><span>확인 필요</span><strong className={activeAlerts.length?"alertCount":""}>{activeAlerts.length.toString().padStart(2,"0")}</strong><small>{activeAlerts.length?"우선 확인하세요":"현재 이상 없음"}</small></div><div><span>평균 진행률</span><strong>{items.length?Math.round(items.reduce((n,x)=>n+x.progress,0)/items.length*100):0}%</strong><small>전체 배송 기준</small></div><form onSubmit={createOrder}><p>빠른 작업</p><button disabled={Boolean(orderBusy)}>+ 새 주문 만들기</button></form></section>
  <section className="mapBoard"><div className="mapHeader"><div className="mapTitle"><p className="eyebrow">LIVE FLEET</p><h2>실시간 운송 지도</h2><div className="mapControls"><div className="mapScope" aria-label="지도 표시 범위"><button type="button" aria-pressed={fleetScope==="LIVE"} className={fleetScope==="LIVE"?"active":""} onClick={()=>setFleetScope("LIVE")}>운송 중 {liveItems.length}</button><button type="button" aria-pressed={fleetScope==="ALL"} className={fleetScope==="ALL"?"active":""} onClick={()=>setFleetScope("ALL")}>전체 {items.length}</button></div><label className="mapSearch" htmlFor="fleetSearch"><span>검색</span><input id="fleetSearch" type="search" value={fleetQuery} onChange={event=>setFleetQuery(event.target.value)} placeholder="차량 · 주문 · 지역"/></label></div></div>{focus&&visibleItems.some(item=>item.id===focus.id)&&<div className="focusStats"><div className="focusRoute"><small>선택한 차량</small><strong>{focus.vehicleId}</strong><span>{focus.originName} → {focus.destinationName}</span></div><span><small>진행률</small>{Math.round(focus.progress*100)}%</span><span><small>거리</small>{focusRoute?`${(focusRoute.distanceMeters/1000).toFixed(1)} km`:"계산 중"}</span><span><small>도착 예정</small>{focus.eta?new Date(focus.eta).toLocaleTimeString("ko-KR",{hour:"2-digit",minute:"2-digit"}):focus.status==="DELIVERED"?"도착":focusRoute?new Date(focusRoute.plannedEta).toLocaleTimeString("ko-KR",{hour:"2-digit",minute:"2-digit"}):"—"}</span></div>}</div>
   <FleetMap deliveries={visibleItems} routes={routes} telemetry={telemetry} selectedId={selected} onSelect={setSelected} emptyMessage={fleetQuery?`“${fleetQuery}” 검색 결과가 없습니다. 검색어를 지우거나 범위를 전환해 주세요.`:undefined}/></section>
  <AlertOperationsPanel alerts={alerts} deliveries={items} busyId={alertBusy} onSelect={focusDelivery} onAcknowledge={acknowledgeAlert}/>
  <DailyKpiPanel rows={kpis} csvUrl={`${API}/api/reports/daily-kpis.csv?days=30`} pdfUrl={`${API}/api/reports/daily-kpis.pdf?days=30`}/></>}
  {workspace==="orders"&&<><OrderFlowPanel orders={orders} busyId={orderBusy} onCreate={()=>createOrder()} onDispatch={dispatchOrder}/>
  <section className="board"><div className="boardTitle"><h2>Fleet telemetry</h2><span>{visibleItems.length} shown · {items.length} total · {fleetScope} scope</span></div>
  <div className="grid">{visibleItems.length===0?<div className="empty">{items.length===0?"배송을 생성하면 차량 위치 이벤트가 지도와 목록에 표시됩니다.":"현재 범위와 검색 조건에 맞는 배송이 없습니다."}</div>:visibleItems.map(d=>{const count=activeAlerts.filter(alert=>alert.deliveryId===d.id).length;return <article key={d.id} onClick={()=>focusDelivery(d.id)} className={selected===d.id?"selected":""}><div className="row"><span className={`badge ${d.status.toLowerCase()}`}>{d.status.replace("_"," ")}</span><b>{count>0&&<i className="cardAlert">{count}</i>}{d.vehicleId}</b></div><h3>{d.orderNumber}</h3><p>{d.originName} <em>→</em> {d.destinationName}</p><div className="track"><i style={{width:`${d.progress*100}%`}}/></div><div className="meta"><span>{Math.round(d.progress*100)}% complete</span><span>{d.currentLat?.toFixed(4)}, {d.currentLon?.toFixed(4)}</span></div></article>})}</div></section></>}
  {workspace==="warehouse"&&<section className="warehouseBoard"><div className="warehouseHeader"><div><p className="eyebrow">WAREHOUSE / INVENTORY</p><h2>Stock control</h2></div><div className="warehouseActions"><button disabled={warehouseBusy} onClick={receiveStock}>+ RECEIVE 10</button><button disabled={warehouseBusy} onClick={pickAndDispatch}>PICK & DISPATCH 4</button></div></div>
   <div className="warehouseGrid"><div className="stockPane"><h4>AVAILABLE STOCK</h4>{stocks.length===0?<p className="warehouseEmpty">No inventory yet. Receive demo stock to begin.</p>:<div className="stockTable"><div className="stockRow head"><span>LOCATION / SKU</span><span>ON HAND</span><span>RESERVED</span><span>AVAILABLE</span></div>{stocks.slice(0,8).map(s=><div className="stockRow" key={s.id}><span><b>{s.warehouseId}</b><small>{s.sku}</small></span><strong>{s.onHand}</strong><strong>{s.reserved}</strong><strong className="available">{s.available}</strong></div>)}</div>}</div>
   <div className="ledgerPane"><h4>RECENT LEDGER</h4>{ledger.length===0?<p className="warehouseEmpty">Inventory movements will appear here.</p>:ledger.slice(0,7).map(e=><div className="ledgerRow" key={e.id}><span className={`movement ${e.transactionType.toLowerCase()}`}>{e.transactionType}</span><span><b>{e.sku}</b><small>{e.warehouseId}</small></span><span className="delta">{e.onHandDelta>0?`+${e.onHandDelta}`:e.onHandDelta||`R +${e.reservedDelta}`}</span></div>)}</div></div>
   <div className="taskStrip"><span>{tasks.filter(t=>t.status==="PICKED").length} awaiting dispatch</span><span>{tasks.filter(t=>t.status==="DISPATCHED").length} dispatched</span><span>{ledger.length} ledger movements loaded</span></div>
  </section>}
  {workspace==="recovery"&&<><div className="recoveryNotice"><span>{deadLetterTotal}</span><div><strong>검토 대기 중인 이벤트</strong><p>재처리 또는 폐기 전에 이벤트 내용과 영향 범위를 확인하세요. 모든 작업은 감사 이력에 기록됩니다.</p></div></div><ReplayOperationsPanel events={deadLetters} totalEvents={deadLetterTotal} audits={replayAudits} busyId={replayBusy} pageBusy={replayPageBusy} discardPlan={discardPlan} discardPlanBusy={discardPlanBusy} onReplay={replay} onDiscard={discard} onLoadMore={loadMoreReplay} onPrepareDiscard={prepareDiscard} onExecuteDiscard={executeDiscard} onResetDiscardPlan={()=>setDiscardPlan(undefined)}/>
  <OutboxRecoveryPanel failures={outboxFailures} audits={outboxAudits} busyId={outboxBusy} onRetry={retryOutbox}/></>}
  {workspace==="settings"&&<AlertPolicyPanel policies={policies} audits={policyAudits} deliveries={items} busy={policyBusy} onSave={savePolicy} onReset={resetPolicy} onRestore={restorePolicy}/>}</>}</div>
 </main>
}

function WorkspaceLoading({label}:{label:string}){
 return <section className="workspaceLoading" role="status" aria-live="polite"><div className="loadingMark"><i/><i/><i/></div><div><strong>{label} 데이터를 불러오는 중입니다</strong><span>최신 운영 정보를 안전하게 동기화하고 있습니다.</span></div></section>;
}

function pollAfterCompletion(task:()=>Promise<unknown>,delayMs:number){
 let stopped=false;let timer:number|undefined;
 const poll=async()=>{try{await task()}catch{}finally{if(!stopped)timer=window.setTimeout(poll,delayMs)}};
 void poll();
 return()=>{stopped=true;if(timer!==undefined)window.clearTimeout(timer)};
}

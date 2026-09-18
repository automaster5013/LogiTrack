"use client";
import { FormEvent, useEffect, useState } from "react";
import dynamic from "next/dynamic";
import type { Delivery } from "./types";

const FleetMap=dynamic(()=>import("./components/FleetMap"),{ssr:false});
const API=process.env.NEXT_PUBLIC_API_URL || "http://localhost:8080";

export default function Home(){
 const [items,setItems]=useState<Delivery[]>([]); const [connected,setConnected]=useState(false); const [error,setError]=useState(""); const [selected,setSelected]=useState<string>();
 const load=()=>fetch(`${API}/api/deliveries`).then(r=>r.json()).then(setItems).catch(()=>setError("API에 연결할 수 없습니다."));
 useEffect(()=>{load(); const source=new EventSource(`${API}/api/stream/deliveries`); source.onopen=()=>setConnected(true); source.onerror=()=>setConnected(false);
  source.addEventListener("delivery-update",e=>{const next=JSON.parse((e as MessageEvent).data);setItems(old=>[next,...old.filter(x=>x.id!==next.id)])});return()=>source.close()},[]);
 useEffect(()=>{if(!selected&&items.length)setSelected(items[0].id)},[items,selected]);
 async function create(e:FormEvent){e.preventDefault();setError("");const response=await fetch(`${API}/api/deliveries`,{method:"POST",headers:{"Content-Type":"application/json","Idempotency-Key":crypto.randomUUID()},body:JSON.stringify({orderNumber:`ORD-${Date.now().toString().slice(-6)}`,vehicleId:`TRUCK-${Math.ceil(Math.random()*9).toString().padStart(2,"0")}`,origin:{name:"Seoul Hub",lat:37.5665,lon:126.978},destination:{name:"Incheon DC",lat:37.4563,lon:126.7052}})});if(!response.ok)setError("배송 생성에 실패했습니다.");else load()}
 const focus=items.find(x=>x.id===selected);
 return <main><header><div><p className="eyebrow">OPERATIONS / LIVE</p><h1>LogiTrack Control Tower</h1></div><div className={`signal ${connected?"on":""}`}><i/>{connected?"LIVE STREAM":"RECONNECTING"}</div></header>
  <section className="hero"><div><span>ACTIVE DELIVERIES</span><strong>{items.filter(x=>x.status!=="DELIVERED").length.toString().padStart(2,"0")}</strong></div><div><span>COMPLETED</span><strong>{items.filter(x=>x.status==="DELIVERED").length.toString().padStart(2,"0")}</strong></div><div><span>FLEET PROGRESS</span><strong>{items.length?Math.round(items.reduce((n,x)=>n+x.progress,0)/items.length*100):0}%</strong></div><form onSubmit={create}><button>+ SIMULATE DELIVERY</button></form></section>
  {error&&<p className="error">{error}</p>}
  <section className="mapBoard"><div className="mapHeader"><div><p className="eyebrow">GEOSPATIAL OVERVIEW</p><h2>Live fleet map</h2></div>{focus&&<div className="focusStats"><span><small>FOCUS</small>{focus.vehicleId}</span><span><small>PROGRESS</small>{Math.round(focus.progress*100)}%</span><span><small>ETA</small>{focus.eta?new Date(focus.eta).toLocaleTimeString("ko-KR",{hour:"2-digit",minute:"2-digit"}):"ARRIVED"}</span></div>}</div>
   <FleetMap deliveries={items} selectedId={selected} onSelect={setSelected}/></section>
  <section className="board"><div className="boardTitle"><h2>Fleet telemetry</h2><span>{items.length} shipments · select to focus map</span></div>
  <div className="grid">{items.length===0?<div className="empty">배송을 생성하면 차량 위치 이벤트가 지도와 목록에 표시됩니다.</div>:items.map(d=><article key={d.id} onClick={()=>setSelected(d.id)} className={selected===d.id?"selected":""}><div className="row"><span className={`badge ${d.status.toLowerCase()}`}>{d.status.replace("_"," ")}</span><b>{d.vehicleId}</b></div><h3>{d.orderNumber}</h3><p>{d.originName} <em>→</em> {d.destinationName}</p><div className="track"><i style={{width:`${d.progress*100}%`}}/></div><div className="meta"><span>{Math.round(d.progress*100)}% complete</span><span>{d.currentLat?.toFixed(4)}, {d.currentLon?.toFixed(4)}</span></div></article>)}</div></section>
 </main>
}

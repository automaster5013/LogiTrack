"use client";

import { useEffect, useRef, useState } from "react";
import { AttributionControl, GeoJSONSource, Map, NavigationControl, Popup, ScaleControl, setWorkerUrl } from "maplibre-gl";
import type { FilterSpecification } from "maplibre-gl";
import type { FeatureCollection, Geometry } from "geojson";
import type { Delivery, RouteSnapshot, TelemetryPoint } from "../types";

setWorkerUrl("/maplibre/maplibre-gl-worker.mjs");
const STYLE = process.env.NEXT_PUBLIC_MAP_STYLE_URL || "https://tiles.openfreemap.org/styles/liberty";
const MAP_LOCALE={
  "AttributionControl.ToggleAttribution":"지도 정보 표시",
  "Map.Title":"운송 차량 지도",
  "NavigationControl.ResetBearing":"드래그하여 지도를 회전하고 클릭하여 북쪽으로 초기화",
  "NavigationControl.ZoomIn":"지도 확대",
  "NavigationControl.ZoomOut":"지도 축소",
  "CooperativeGesturesHandler.WindowsHelpText":"Ctrl 키를 누른 채 스크롤하여 지도를 확대하거나 축소하세요",
  "CooperativeGesturesHandler.MacHelpText":"⌘ 키를 누른 채 스크롤하여 지도를 확대하거나 축소하세요",
  "CooperativeGesturesHandler.MobileHelpText":"두 손가락으로 지도를 이동하세요"
};

type Props = { deliveries: Delivery[]; routes: RouteSnapshot[]; telemetry: TelemetryPoint[]; selectedId?: string; onSelect: (id: string) => void; emptyMessage?: string };
const STATUS_COPY:Record<Delivery["status"],string>={CREATED:"배송 준비",IN_TRANSIT:"운송 중",DELAYED:"지연",DELIVERED:"배송 완료"};
const mapMotionDuration=()=>window.matchMedia("(prefers-reduced-motion: reduce)").matches?0:900;

function routeIndex(routes: RouteSnapshot[]) {
  const indexed=new globalThis.Map<string,[number,number][]>();
  for(const route of routes) if(!indexed.has(route.deliveryId)) indexed.set(route.deliveryId,route.geometry.coordinates);
  return indexed;
}

function estimatedCoordinates(route:[number,number][],progress:number,current:[number,number]) {
  const end=Math.max(1,Math.ceil(progress*(route.length-1))+1);
  return [...route.slice(0,end),current];
}

function selectedTelemetryFreshness(delivery:Delivery,telemetry:TelemetryPoint[]){
  const timestamps=[delivery.lastTelemetryAt,...telemetry.filter(point=>point.deliveryId===delivery.id).map(point=>point.occurredAt)]
    .filter((value):value is string=>Boolean(value)).map(value=>new Date(value).getTime()).filter(value=>!Number.isNaN(value));
  if(!timestamps.length)return {label:"위치 이벤트 없음",stale:true};
  const ageMinutes=Math.max(0,Math.floor((Date.now()-Math.max(...timestamps))/60_000));
  if(ageMinutes<1)return {label:"위치 방금 수신",stale:false};
  return {label:`위치 ${ageMinutes<60?`${ageMinutes}분`:`${Math.floor(ageMinutes/60)}시간`} 전 수신`,stale:ageMinutes>=5};
}

function features(deliveries: Delivery[], routes: RouteSnapshot[], telemetry: TelemetryPoint[]): FeatureCollection<Geometry> {
  const result: FeatureCollection<Geometry>["features"] = [];
  const indexed=routeIndex(routes);
  const tracks=new globalThis.Map<string,TelemetryPoint[]>();
  for(const point of telemetry) tracks.set(point.deliveryId,[...(tracks.get(point.deliveryId)||[]),point]);
  for (const d of deliveries) {
    const current: [number, number] = [d.currentLon ?? d.originLon, d.currentLat ?? d.originLat];
    const origin: [number, number] = [d.originLon, d.originLat];
    const destination: [number, number] = [d.destinationLon, d.destinationLat];
    const planned=indexed.get(d.id) || [origin,destination];
    const actual=(tracks.get(d.id)||[]).sort((a,b)=>a.occurredAt.localeCompare(b.occurredAt)).map(point=>[point.longitude,point.latitude] as [number,number]);
    const eta=d.eta?new Date(d.eta):undefined;
    const overdue=Boolean(d.status!=="DELIVERED"&&eta&&!Number.isNaN(eta.getTime())&&eta.getTime()<Date.now());
    result.push(
      { type:"Feature", properties:{kind:"route",id:d.id,status:d.status}, geometry:{type:"LineString",coordinates:planned} },
      { type:"Feature", properties:{kind:"traveled",id:d.id,status:d.status,actual:actual.length>0}, geometry:{type:"LineString",coordinates:actual.length?[origin,...actual]:estimatedCoordinates(planned,d.progress,current)} },
      { type:"Feature", properties:{kind:"vehicle",id:d.id,label:d.vehicleId,status:d.status,overdue}, geometry:{type:"Point",coordinates:current} },
      { type:"Feature", properties:{kind:"origin",id:d.id,label:d.originName}, geometry:{type:"Point",coordinates:origin} },
      { type:"Feature", properties:{kind:"destination",id:d.id,label:d.destinationName}, geometry:{type:"Point",coordinates:destination} },
    );
  }
  return { type:"FeatureCollection", features:result };
}

export default function FleetMap({deliveries,routes,telemetry,selectedId,onSelect,emptyMessage}:Props){
  const shellRef=useRef<HTMLDivElement>(null); const host=useRef<HTMLDivElement>(null); const expandButtonRef=useRef<HTMLButtonElement>(null); const mapRef=useRef<Map|null>(null); const popupRef=useRef<Popup|null>(null); const loaded=useRef(false); const retryingRef=useRef(false);
  const deliveriesRef=useRef(deliveries); const routesRef=useRef(routes); const telemetryRef=useRef(telemetry); const selectedRef=useRef(selectedId);
  deliveriesRef.current=deliveries; routesRef.current=routes; telemetryRef.current=telemetry; selectedRef.current=selectedId;
  const [mapError,setMapError]=useState(false); const [mapReady,setMapReady]=useState(false); const [mapRetry,setMapRetry]=useState(0); const [mapRecovering,setMapRecovering]=useState(false); const [legendExpanded,setLegendExpanded]=useState(false); const [mapExpanded,setMapExpanded]=useState(false);
  const retryMap=()=>{if(retryingRef.current)return;retryingRef.current=true;setMapRecovering(true);setMapRetry(value=>value+1)};

  useEffect(()=>{
    if(!host.current||mapRef.current)return;
    if(mapRetry===0)setMapError(false);setMapReady(false);loaded.current=false;
    const map=new Map({container:host.current,style:STYLE,center:[126.84,37.51],zoom:9.6,pitch:36,bearing:-6,locale:MAP_LOCALE,
      attributionControl:false,maxPitch:65,cooperativeGestures:true});
    mapRef.current=map;
    map.addControl(new NavigationControl({visualizePitch:true}),"top-right");
    map.addControl(new ScaleControl({unit:"metric"}),"bottom-left");
    map.addControl(new AttributionControl({compact:true}),"bottom-right");
    const failLoad=()=>{if(!loaded.current){retryingRef.current=false;setMapError(true);setMapRecovering(false)}};
    const loadTimeout=window.setTimeout(failLoad,12000);
    map.on("error",failLoad);
    map.on("load",()=>{
      window.clearTimeout(loadTimeout); loaded.current=true; retryingRef.current=false; setMapError(false); setMapRecovering(false);
      map.addSource("fleet",{type:"geojson",data:features(deliveriesRef.current,routesRef.current,telemetryRef.current)});
      const selectedFilter=(kind:string)=>["all",["==",["get","kind"],kind],["==",["get","id"],selectedRef.current||""]] as FilterSpecification;
      map.addLayer({id:"planned-shadow",type:"line",source:"fleet",filter:["==",["get","kind"],"route"],paint:{"line-color":"#ffffff","line-width":5,"line-opacity":0.28}});
      map.addLayer({id:"planned",type:"line",source:"fleet",filter:["==",["get","kind"],"route"],paint:{"line-color":"#38564d","line-width":1.25,"line-dasharray":[2,3],"line-opacity":0.22}});
      map.addLayer({id:"traveled",type:"line",source:"fleet",filter:["==",["get","kind"],"traveled"],paint:{"line-color":"#76a930","line-width":2.25,"line-opacity":0.24}});
      map.addLayer({id:"selected-planned-casing",type:"line",source:"fleet",filter:selectedFilter("route"),paint:{"line-color":"#ffffff","line-width":7,"line-opacity":0.9}});
      map.addLayer({id:"selected-planned",type:"line",source:"fleet",filter:selectedFilter("route"),paint:{"line-color":"#17372d","line-width":3,"line-dasharray":[2,2],"line-opacity":1}});
      map.addLayer({id:"selected-traveled-casing",type:"line",source:"fleet",filter:selectedFilter("traveled"),paint:{"line-color":"#17372d","line-width":9,"line-opacity":0.8}});
      map.addLayer({id:"selected-traveled",type:"line",source:"fleet",filter:selectedFilter("traveled"),paint:{"line-color":"#a8ef18","line-width":5.5,"line-opacity":1}});
      map.addLayer({id:"hubs",type:"circle",source:"fleet",filter:["all",["in",["get","kind"],["literal",["origin","destination"]]],["==",["get","id"],selectedRef.current||""]],paint:{"circle-radius":6,"circle-color":"#ffffff","circle-stroke-color":"#17372d","circle-stroke-width":2.5}});
      map.addLayer({id:"vehicles-halo",type:"circle",source:"fleet",filter:["==",["get","kind"],"vehicle"],paint:{"circle-radius":12,"circle-color":["case",["==",["get","status"],"DELAYED"],"#ff6b46",["==",["get","overdue"],true],"#f4a62a","#a7ef19"],"circle-opacity":0.2}});
      map.addLayer({id:"vehicles",type:"circle",source:"fleet",filter:["==",["get","kind"],"vehicle"],paint:{"circle-radius":6.5,"circle-color":["case",["==",["get","status"],"DELAYED"],"#ff5a36",["==",["get","overdue"],true],"#d77b00","#17372d"],"circle-stroke-color":"#ffffff","circle-stroke-width":2}});
      map.addLayer({id:"selected-vehicle-glow",type:"circle",source:"fleet",filter:selectedFilter("vehicle"),paint:{"circle-radius":19,"circle-color":"#b9f227","circle-opacity":0.22}});
      map.addLayer({id:"selected-vehicle",type:"circle",source:"fleet",filter:selectedFilter("vehicle"),paint:{"circle-radius":12,"circle-color":"rgba(0,0,0,0)","circle-stroke-color":"#b9f227","circle-stroke-width":4}});
      map.addLayer({id:"vehicle-labels",type:"symbol",source:"fleet",filter:selectedFilter("vehicle"),layout:{"text-field":["get","label"],"text-size":12,"text-offset":[0,1.75],"text-anchor":"top","text-font":["Noto Sans Regular"]},paint:{"text-color":"#10221d","text-halo-color":"#ffffff","text-halo-width":2.5}});
      map.on("mouseenter","vehicles",event=>{
        map.getCanvas().style.cursor="pointer";
        const id=event.features?.[0]?.properties?.id as string|undefined;
        const delivery=deliveriesRef.current.find(item=>item.id===id);
        if(!delivery)return;
        const coordinates:[number,number]=[delivery.currentLon??delivery.originLon,delivery.currentLat??delivery.originLat];
        const eta=delivery.eta?new Date(delivery.eta):undefined;
        const overdue=delivery.status!=="DELIVERED"&&eta&&!Number.isNaN(eta.getTime())&&eta.getTime()<Date.now();
        const preview=document.createElement("div"); preview.className="fleetMapPreview";
        const title=document.createElement("strong"); title.textContent=delivery.vehicleId;
        const state=document.createElement("span"); state.className=delivery.status==="DELAYED"?"delayed":overdue?"overdue":"live"; state.textContent=`${delivery.status==="DELAYED"?"지연":overdue?"예정 초과":STATUS_COPY[delivery.status]} · ${Math.round(delivery.progress*100)}%`;
        const route=document.createElement("small"); route.textContent=`${delivery.originName} → ${delivery.destinationName}`;
        preview.append(title,state,route);
        popupRef.current?.remove();
        popupRef.current=new Popup({closeButton:false,closeOnClick:false,offset:18,className:"fleetMapPopup"}).setLngLat(coordinates).setDOMContent(preview).addTo(map);
      });
      map.on("mouseleave","vehicles",()=>{map.getCanvas().style.cursor="";popupRef.current?.remove();popupRef.current=null});
      map.on("click","vehicles",event=>{popupRef.current?.remove();popupRef.current=null;const id=event.features?.[0]?.properties?.id;if(id)onSelect(id)});
      const selected=deliveriesRef.current.find(x=>x.id===selectedRef.current);
      if(selected)fitDelivery(map,selected,routesRef.current,telemetryRef.current);
      map.once("idle",()=>{setMapReady(true);if(mapRetry>0)map.getCanvas().focus()});
    });
    return()=>{window.clearTimeout(loadTimeout);popupRef.current?.remove();popupRef.current=null;map.remove();mapRef.current=null;loaded.current=false};
  },[mapRetry]);

  useEffect(()=>{
    if(!mapError||mapRecovering)return;
    const handleOnline=()=>retryMap();
    window.addEventListener("online",handleOnline);
    return()=>window.removeEventListener("online",handleOnline);
  },[mapError,mapRecovering]);

  useEffect(()=>{
    const map=mapRef.current;if(!map||!loaded.current)return;
    (map.getSource("fleet") as GeoJSONSource)?.setData(features(deliveries,routes,telemetry));
  },[deliveries,routes,telemetry]);

  useEffect(()=>{
    const map=mapRef.current;if(!map||!loaded.current||!selectedId)return;
    const d=deliveries.find(x=>x.id===selectedId);if(!d)return;
    for(const layer of ["selected-vehicle-glow","selected-vehicle","vehicle-labels"]) map.setFilter(layer,["all",["==",["get","kind"],"vehicle"],["==",["get","id"],selectedId]]);
    for(const layer of ["selected-planned-casing","selected-planned"]) map.setFilter(layer,["all",["==",["get","kind"],"route"],["==",["get","id"],selectedId]]);
    for(const layer of ["selected-traveled-casing","selected-traveled"]) map.setFilter(layer,["all",["==",["get","kind"],"traveled"],["==",["get","id"],selectedId]]);
    map.setFilter("hubs",["all",["in",["get","kind"],["literal",["origin","destination"]]],["==",["get","id"],selectedId]]);
    fitDelivery(map,d,routes,telemetry);
  },[selectedId,routes,telemetry]);

  useEffect(()=>{
    const map=mapRef.current;
    const frame=window.requestAnimationFrame(()=>map?.resize());
    if(!mapExpanded)return()=>window.cancelAnimationFrame(frame);
    const previousOverflow=document.body.style.overflow;
    const previousFocus=document.activeElement instanceof HTMLElement?document.activeElement:null;
    const disabledBackground:Array<{element:HTMLElement;inert:boolean;ariaHidden:string|null}>=[];
    let modalBranch:HTMLElement|null=shellRef.current;
    while(modalBranch?.parentElement&&modalBranch!==document.body){
      for(const sibling of modalBranch.parentElement.children){
        if(!(sibling instanceof HTMLElement)||sibling===modalBranch)continue;
        disabledBackground.push({element:sibling,inert:sibling.inert,ariaHidden:sibling.getAttribute("aria-hidden")});
        sibling.inert=true;
        sibling.setAttribute("aria-hidden","true");
      }
      modalBranch=modalBranch.parentElement;
    }
    document.body.style.overflow="hidden";
    expandButtonRef.current?.focus();
    const handleModalKey=(event:KeyboardEvent)=>{
      if(event.key==="Escape"){event.preventDefault();setMapExpanded(false);return}
      if(event.key!=="Tab")return;
      const focusable=Array.from(shellRef.current?.querySelectorAll<HTMLElement>('button:not([disabled]),[href],select:not([disabled]),[tabindex]:not([tabindex="-1"])')||[])
        .filter(element=>!element.hasAttribute("hidden")&&element.getAttribute("aria-hidden")!=="true");
      if(!focusable.length)return;
      const first=focusable[0]; const last=focusable[focusable.length-1]; const active=document.activeElement;
      if(event.shiftKey&&(active===first||!shellRef.current?.contains(active))){event.preventDefault();last.focus()}
      else if(!event.shiftKey&&(active===last||!shellRef.current?.contains(active))){event.preventDefault();first.focus()}
    };
    document.addEventListener("keydown",handleModalKey);
    return()=>{window.cancelAnimationFrame(frame);document.body.style.overflow=previousOverflow;document.removeEventListener("keydown",handleModalKey);for(const {element,inert,ariaHidden} of disabledBackground){element.inert=inert;if(ariaHidden===null)element.removeAttribute("aria-hidden");else element.setAttribute("aria-hidden",ariaHidden)}previousFocus?.focus()};
  },[mapExpanded]);

  const selected=deliveries.find(delivery=>delivery.id===selectedId);
  const selectedFreshness=selected?selectedTelemetryFreshness(selected,telemetry):undefined;
  const overdueCount=deliveries.filter(delivery=>{if(delivery.status==="DELIVERED"||!delivery.eta)return false;const eta=new Date(delivery.eta);return !Number.isNaN(eta.getTime())&&eta.getTime()<Date.now()}).length;
  const overdueLabel=overdueCount?` 예정 초과 ${overdueCount}대.`:"";
  const mapLabel=selected
    ? `${deliveries.length}대의 차량 운행 지도.${overdueLabel} ${selected.vehicleId} 차량이 선택됨`
    : `${deliveries.length}대의 차량 운행 지도.${overdueLabel}`;
  const showEntireFleet=()=>{const map=mapRef.current;if(map&&deliveries.length)fitFleet(map,deliveries)};

  return <div ref={shellRef} id="fleet-map-panel" className={`mapShell ${mapReady?"ready":""} ${mapExpanded?"mapExpanded":""}`} role={mapExpanded?"dialog":"region"} aria-modal={mapExpanded||undefined} aria-label={mapLabel}>
    <div ref={host} className="mapCanvas"/>
    {mapError&&<div className="mapError" role="alert"><b>{mapRecovering?"지도를 다시 연결하고 있습니다":"지도를 불러오지 못했습니다"}</b><span>{mapRecovering?"현재 차량 검색과 선택을 유지한 채 지도만 복구합니다.":"지도 타일 연결을 확인하세요. 배송 데이터 스트림은 계속 동작합니다."}</span><button type="button" disabled={mapRecovering} onClick={retryMap}>{mapRecovering?"지도 연결 중…":"지도 다시 불러오기"}</button></div>}
    {!mapError&&deliveries.length===0&&<div className="mapEmpty"><b>표시할 차량이 없습니다</b><span>{emptyMessage||"범위를 전환하거나 새 배송을 생성해 주세요."}</span></div>}
    <div className={`mapLegend ${legendExpanded?"expanded":"compact"}`} aria-label="지도 범례"><button type="button" className="mapLegendToggle" aria-expanded={legendExpanded} aria-controls="fleet-map-legend-items" onClick={()=>setLegendExpanded(value=>!value)}><span><i className="mapReadyDot"/> 지도 범례</span><small>{deliveries.length}대 표시</small><b>{legendExpanded?"접기":"보기"}</b></button><div id="fleet-map-legend-items" className="mapLegendItems" hidden={!legendExpanded}><span><i className="liveDot"/> 운송 차량</span><span><i className="overdueDot"/> 예정 초과</span><span><i className="delayedDot"/> 지연 차량</span><span><i className="selectedDot"/> 선택 차량</span><span><i className="travelDot"/> 실제 이동</span><span><i className="routeDot"/> 계획 경로</span><p>차량을 선택하면 상세 경로와 거점이 강조됩니다.</p></div></div>
    <button ref={expandButtonRef} type="button" className="mapExpand" aria-expanded={mapExpanded} aria-controls="fleet-map-panel" aria-label={mapExpanded?"지도 원래 크기로":"지도 확대 보기"} onClick={()=>setMapExpanded(value=>!value)}>{mapExpanded?"축소":"확대"}</button>
    {deliveries.length>1&&<button type="button" className="mapReset" onClick={showEntireFleet}>전체 차량 보기</button>}
    {mapExpanded&&selected&&<aside className="mapExpandedHud" aria-label="확대 지도 선택 차량 정보" aria-live="polite">
      <div><small>선택 차량</small><strong>{selected.vehicleId}</strong><span className={`mapHudState ${selected.status.toLowerCase()}`}>{STATUS_COPY[selected.status]}</span></div>
      <p>{selected.originName} <b aria-hidden="true">→</b> {selected.destinationName}</p>
      <dl><div><dt>주문</dt><dd>{selected.orderNumber}</dd></div><div><dt>진행률</dt><dd>{Math.round(selected.progress*100)}%</dd></div><div className={selectedFreshness?.stale?"stale":"fresh"}><dt>최근 위치</dt><dd>{selectedFreshness?.label}</dd></div></dl>
    </aside>}
  </div>;
}

function fitFleet(map:Map,deliveries:Delivery[]) {
  const coordinates=deliveries.flatMap(delivery=>[
    [delivery.originLon,delivery.originLat],
    [delivery.destinationLon,delivery.destinationLat],
    [delivery.currentLon??delivery.originLon,delivery.currentLat??delivery.originLat]
  ] as [number,number][]);
  const lons=coordinates.map(point=>point[0]); const lats=coordinates.map(point=>point[1]);
  map.fitBounds([[Math.min(...lons),Math.min(...lats)],[Math.max(...lons),Math.max(...lats)]],{padding:70,duration:mapMotionDuration(),maxZoom:10.5});
}

function fitDelivery(map:Map,delivery:Delivery,routes:RouteSnapshot[],telemetry:TelemetryPoint[]) {
  const route=routeIndex(routes).get(delivery.id)||[[delivery.originLon,delivery.originLat],[delivery.destinationLon,delivery.destinationLat]];
  const actual=telemetry.filter(point=>point.deliveryId===delivery.id).map(point=>[point.longitude,point.latitude] as [number,number]);
  const coordinates=[...route,...actual];
  const lons=coordinates.map(point=>point[0]); const lats=coordinates.map(point=>point[1]);
  map.fitBounds([[Math.min(...lons),Math.min(...lats)],[Math.max(...lons),Math.max(...lats)]],{padding:90,duration:mapMotionDuration(),maxZoom:12.5});
}

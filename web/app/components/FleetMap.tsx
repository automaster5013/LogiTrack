"use client";

import { useEffect, useRef, useState } from "react";
import { AttributionControl, GeoJSONSource, Map, NavigationControl, ScaleControl, setWorkerUrl } from "maplibre-gl";
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

function routeIndex(routes: RouteSnapshot[]) {
  const indexed=new globalThis.Map<string,[number,number][]>();
  for(const route of routes) if(!indexed.has(route.deliveryId)) indexed.set(route.deliveryId,route.geometry.coordinates);
  return indexed;
}

function estimatedCoordinates(route:[number,number][],progress:number,current:[number,number]) {
  const end=Math.max(1,Math.ceil(progress*(route.length-1))+1);
  return [...route.slice(0,end),current];
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
  const host=useRef<HTMLDivElement>(null); const mapRef=useRef<Map|null>(null); const loaded=useRef(false);
  const deliveriesRef=useRef(deliveries); const routesRef=useRef(routes); const telemetryRef=useRef(telemetry); const selectedRef=useRef(selectedId);
  deliveriesRef.current=deliveries; routesRef.current=routes; telemetryRef.current=telemetry; selectedRef.current=selectedId;
  const [mapError,setMapError]=useState(false); const [mapReady,setMapReady]=useState(false);

  useEffect(()=>{
    if(!host.current||mapRef.current)return;
    const map=new Map({container:host.current,style:STYLE,center:[126.84,37.51],zoom:9.6,pitch:42,bearing:-8,locale:MAP_LOCALE,
      attributionControl:false,maxPitch:65});
    mapRef.current=map;
    map.addControl(new NavigationControl({visualizePitch:true}),"top-right");
    map.addControl(new ScaleControl({unit:"metric"}),"bottom-left");
    map.addControl(new AttributionControl({compact:true}),"bottom-right");
    const loadTimeout=window.setTimeout(()=>{if(!loaded.current)setMapError(true)},12000);
    map.on("load",()=>{
      window.clearTimeout(loadTimeout); loaded.current=true; setMapError(false);
      map.addSource("fleet",{type:"geojson",data:features(deliveriesRef.current,routesRef.current,telemetryRef.current)});
      map.addLayer({id:"planned-shadow",type:"line",source:"fleet",filter:["==",["get","kind"],"route"],paint:{"line-color":"#ffffff","line-width":7,"line-opacity":0.72}});
      map.addLayer({id:"planned",type:"line",source:"fleet",filter:["==",["get","kind"],"route"],paint:{"line-color":"#315048","line-width":1.5,"line-dasharray":[2,2],"line-opacity":0.3}});
      map.addLayer({id:"traveled",type:"line",source:"fleet",filter:["==",["get","kind"],"traveled"],paint:{"line-color":"#7ebd20","line-width":3,"line-opacity":0.38}});
      map.addLayer({id:"selected-planned",type:"line",source:"fleet",filter:["all",["==",["get","kind"],"route"],["==",["get","id"],selectedRef.current||""]],paint:{"line-color":"#17372d","line-width":3,"line-dasharray":[2,2],"line-opacity":0.95}});
      map.addLayer({id:"selected-traveled",type:"line",source:"fleet",filter:["all",["==",["get","kind"],"traveled"],["==",["get","id"],selectedRef.current||""]],paint:{"line-color":"#9be900","line-width":6,"line-opacity":1}});
      map.addLayer({id:"hubs",type:"circle",source:"fleet",filter:["in",["get","kind"],["literal",["origin","destination"]]],paint:{"circle-radius":6,"circle-color":"#ffffff","circle-stroke-color":"#19372e","circle-stroke-width":2}});
      map.addLayer({id:"vehicles-halo",type:"circle",source:"fleet",filter:["==",["get","kind"],"vehicle"],paint:{"circle-radius":15,"circle-color":["case",["==",["get","status"],"DELAYED"],"#ff6b46",["==",["get","overdue"],true],"#f4a62a","#a7ef19"],"circle-opacity":0.24}});
      map.addLayer({id:"vehicles",type:"circle",source:"fleet",filter:["==",["get","kind"],"vehicle"],paint:{"circle-radius":8,"circle-color":["case",["==",["get","status"],"DELAYED"],"#ff5a36",["==",["get","overdue"],true],"#d77b00","#172d26"],"circle-stroke-color":"#ffffff","circle-stroke-width":2.5}});
      map.addLayer({id:"selected-vehicle",type:"circle",source:"fleet",filter:["all",["==",["get","kind"],"vehicle"],["==",["get","id"],selectedRef.current||""]],paint:{"circle-radius":13,"circle-color":"rgba(0,0,0,0)","circle-stroke-color":"#b9f227","circle-stroke-width":4}});
      map.addLayer({id:"vehicle-labels",type:"symbol",source:"fleet",filter:["==",["get","kind"],"vehicle"],layout:{"text-field":["get","label"],"text-size":11,"text-offset":[0,1.8],"text-anchor":"top","text-font":["Noto Sans Regular"]},paint:{"text-color":"#10221d","text-halo-color":"#ffffff","text-halo-width":2}});
      map.on("mouseenter","vehicles",()=>map.getCanvas().style.cursor="pointer"); map.on("mouseleave","vehicles",()=>map.getCanvas().style.cursor="");
      map.on("click","vehicles",e=>{const id=e.features?.[0]?.properties?.id;if(id)onSelect(id)});
      const selected=deliveriesRef.current.find(x=>x.id===selectedRef.current);
      if(selected)fitDelivery(map,selected,routesRef.current,telemetryRef.current);
      map.once("idle",()=>setMapReady(true));
    });
    return()=>{window.clearTimeout(loadTimeout);map.remove();mapRef.current=null;loaded.current=false};
  },[]);

  useEffect(()=>{
    const map=mapRef.current;if(!map||!loaded.current)return;
    (map.getSource("fleet") as GeoJSONSource)?.setData(features(deliveries,routes,telemetry));
  },[deliveries,routes,telemetry]);

  useEffect(()=>{
    const map=mapRef.current;if(!map||!loaded.current||!selectedId)return;
    const d=deliveries.find(x=>x.id===selectedId);if(!d)return;
    map.setFilter("selected-vehicle",["all",["==",["get","kind"],"vehicle"],["==",["get","id"],selectedId]]);
    map.setFilter("selected-planned",["all",["==",["get","kind"],"route"],["==",["get","id"],selectedId]]);
    map.setFilter("selected-traveled",["all",["==",["get","kind"],"traveled"],["==",["get","id"],selectedId]]);
    fitDelivery(map,d,routes,telemetry);
  },[selectedId,routes,telemetry]);

  const selected=deliveries.find(delivery=>delivery.id===selectedId);
  const overdueCount=deliveries.filter(delivery=>{if(delivery.status==="DELIVERED"||!delivery.eta)return false;const eta=new Date(delivery.eta);return !Number.isNaN(eta.getTime())&&eta.getTime()<Date.now()}).length;
  const overdueLabel=overdueCount?` 예정 초과 ${overdueCount}대.`:"";
  const mapLabel=selected
    ? `${deliveries.length}대의 차량 운행 지도.${overdueLabel} ${selected.vehicleId} 차량이 선택됨`
    : `${deliveries.length}대의 차량 운행 지도.${overdueLabel}`;
  const showEntireFleet=()=>{const map=mapRef.current;if(map&&deliveries.length)fitFleet(map,deliveries)};

  return <div className={`mapShell ${mapReady?"ready":""}`} role="region" aria-label={mapLabel}><div ref={host} className="mapCanvas"/>{mapError&&<div className="mapError" role="alert"><b>지도를 불러오지 못했습니다</b><span>지도 타일 연결을 확인하세요. 배송 데이터 스트림은 계속 동작합니다.</span><button type="button" onClick={()=>window.location.reload()}>지도 다시 불러오기</button></div>}{!mapError&&deliveries.length===0&&<div className="mapEmpty"><b>표시할 차량이 없습니다</b><span>{emptyMessage||"범위를 전환하거나 새 배송을 생성해 주세요."}</span></div>}<div className="mapLegend" aria-label="지도 범례"><strong>지도 읽는 법</strong><span><i className="liveDot"/> 운송 차량</span><span><i className="overdueDot"/> 예정 초과</span><span><i className="delayedDot"/> 지연 차량</span><span><i className="selectedDot"/> 선택 차량</span><span><i className="travelDot"/> 실제 이동</span><span><i className="routeDot"/> 계획 경로</span><span className="mapReady"><i/> {mapReady?"지도 준비됨":"지도 로딩 중"}</span></div>{deliveries.length>1&&<button type="button" className="mapReset" onClick={showEntireFleet}>전체 차량 보기</button>}<p className="mapHint">차량 점을 선택하면 계획 경로와 실제 이동을 강조합니다</p></div>;
}

function fitFleet(map:Map,deliveries:Delivery[]) {
  const coordinates=deliveries.flatMap(delivery=>[
    [delivery.originLon,delivery.originLat],
    [delivery.destinationLon,delivery.destinationLat],
    [delivery.currentLon??delivery.originLon,delivery.currentLat??delivery.originLat]
  ] as [number,number][]);
  const lons=coordinates.map(point=>point[0]); const lats=coordinates.map(point=>point[1]);
  map.fitBounds([[Math.min(...lons),Math.min(...lats)],[Math.max(...lons),Math.max(...lats)]],{padding:70,duration:900,maxZoom:10.5});
}

function fitDelivery(map:Map,delivery:Delivery,routes:RouteSnapshot[],telemetry:TelemetryPoint[]) {
  const route=routeIndex(routes).get(delivery.id)||[[delivery.originLon,delivery.originLat],[delivery.destinationLon,delivery.destinationLat]];
  const actual=telemetry.filter(point=>point.deliveryId===delivery.id).map(point=>[point.longitude,point.latitude] as [number,number]);
  const coordinates=[...route,...actual];
  const lons=coordinates.map(point=>point[0]); const lats=coordinates.map(point=>point[1]);
  map.fitBounds([[Math.min(...lons),Math.min(...lats)],[Math.max(...lons),Math.max(...lats)]],{padding:90,duration:900,maxZoom:12.5});
}

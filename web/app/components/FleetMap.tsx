"use client";

import { useEffect, useRef, useState } from "react";
import { AttributionControl, GeoJSONSource, Map, NavigationControl, ScaleControl, setWorkerUrl } from "maplibre-gl";
import type { FeatureCollection, Geometry } from "geojson";
import type { Delivery } from "../types";

setWorkerUrl("/maplibre/maplibre-gl-worker.mjs");
const STYLE = process.env.NEXT_PUBLIC_MAP_STYLE_URL || "https://tiles.openfreemap.org/styles/liberty";

type Props = { deliveries: Delivery[]; selectedId?: string; onSelect: (id: string) => void };

function features(deliveries: Delivery[]): FeatureCollection<Geometry> {
  const result: FeatureCollection<Geometry>["features"] = [];
  for (const d of deliveries) {
    const current: [number, number] = [d.currentLon ?? d.originLon, d.currentLat ?? d.originLat];
    const origin: [number, number] = [d.originLon, d.originLat];
    const destination: [number, number] = [d.destinationLon, d.destinationLat];
    result.push(
      { type:"Feature", properties:{kind:"route",id:d.id,status:d.status}, geometry:{type:"LineString",coordinates:[origin,destination]} },
      { type:"Feature", properties:{kind:"traveled",id:d.id,status:d.status}, geometry:{type:"LineString",coordinates:[origin,current]} },
      { type:"Feature", properties:{kind:"vehicle",id:d.id,label:d.vehicleId,status:d.status}, geometry:{type:"Point",coordinates:current} },
      { type:"Feature", properties:{kind:"origin",id:d.id,label:d.originName}, geometry:{type:"Point",coordinates:origin} },
      { type:"Feature", properties:{kind:"destination",id:d.id,label:d.destinationName}, geometry:{type:"Point",coordinates:destination} },
    );
  }
  return { type:"FeatureCollection", features:result };
}

export default function FleetMap({deliveries,selectedId,onSelect}:Props){
  const host=useRef<HTMLDivElement>(null); const mapRef=useRef<Map|null>(null); const loaded=useRef(false);
  const deliveriesRef=useRef(deliveries); const selectedRef=useRef(selectedId);
  deliveriesRef.current=deliveries; selectedRef.current=selectedId;
  const [mapError,setMapError]=useState(false); const [mapReady,setMapReady]=useState(false);

  useEffect(()=>{
    if(!host.current||mapRef.current)return;
    const map=new Map({container:host.current,style:STYLE,center:[126.84,37.51],zoom:9.6,pitch:42,bearing:-8,
      attributionControl:false,maxPitch:65});
    mapRef.current=map;
    map.addControl(new NavigationControl({visualizePitch:true}),"top-right");
    map.addControl(new ScaleControl({unit:"metric"}),"bottom-left");
    map.addControl(new AttributionControl({compact:true}),"bottom-right");
    map.on("error",()=>setMapError(true));
    map.on("load",()=>{
      loaded.current=true; setMapError(false);
      map.addSource("fleet",{type:"geojson",data:features(deliveriesRef.current)});
      map.addLayer({id:"planned-shadow",type:"line",source:"fleet",filter:["==",["get","kind"],"route"],paint:{"line-color":"#ffffff","line-width":7,"line-opacity":0.72}});
      map.addLayer({id:"planned",type:"line",source:"fleet",filter:["==",["get","kind"],"route"],paint:{"line-color":"#1c332c","line-width":2,"line-dasharray":[2,2],"line-opacity":0.68}});
      map.addLayer({id:"traveled",type:"line",source:"fleet",filter:["==",["get","kind"],"traveled"],paint:{"line-color":"#9be900","line-width":5,"line-blur":0.4}});
      map.addLayer({id:"hubs",type:"circle",source:"fleet",filter:["in",["get","kind"],["literal",["origin","destination"]]],paint:{"circle-radius":6,"circle-color":"#ffffff","circle-stroke-color":"#19372e","circle-stroke-width":2}});
      map.addLayer({id:"vehicles-halo",type:"circle",source:"fleet",filter:["==",["get","kind"],"vehicle"],paint:{"circle-radius":15,"circle-color":["case",["==",["get","status"],"DELAYED"],"#ff6b46","#a7ef19"],"circle-opacity":0.22}});
      map.addLayer({id:"vehicles",type:"circle",source:"fleet",filter:["==",["get","kind"],"vehicle"],paint:{"circle-radius":8,"circle-color":["case",["==",["get","status"],"DELAYED"],"#ff5a36","#172d26"],"circle-stroke-color":"#ffffff","circle-stroke-width":2.5}});
      map.addLayer({id:"vehicle-labels",type:"symbol",source:"fleet",filter:["==",["get","kind"],"vehicle"],layout:{"text-field":["get","label"],"text-size":11,"text-offset":[0,1.8],"text-anchor":"top","text-font":["Noto Sans Regular"]},paint:{"text-color":"#10221d","text-halo-color":"#ffffff","text-halo-width":2}});
      map.on("mouseenter","vehicles",()=>map.getCanvas().style.cursor="pointer"); map.on("mouseleave","vehicles",()=>map.getCanvas().style.cursor="");
      map.on("click","vehicles",e=>{const id=e.features?.[0]?.properties?.id;if(id)onSelect(id)});
      const selected=deliveriesRef.current.find(x=>x.id===selectedRef.current);
      if(selected)map.fitBounds([[Math.min(selected.originLon,selected.destinationLon),Math.min(selected.originLat,selected.destinationLat)],[Math.max(selected.originLon,selected.destinationLon),Math.max(selected.originLat,selected.destinationLat)]],{padding:90,duration:0,maxZoom:12.5});
      map.once("idle",()=>setMapReady(true));
    });
    return()=>{map.remove();mapRef.current=null;loaded.current=false};
  },[]);

  useEffect(()=>{
    const map=mapRef.current;if(!map||!loaded.current)return;
    (map.getSource("fleet") as GeoJSONSource)?.setData(features(deliveries));
  },[deliveries]);

  useEffect(()=>{
    const map=mapRef.current;if(!map||!loaded.current||!selectedId)return;
    const d=deliveries.find(x=>x.id===selectedId);if(!d)return;
    map.fitBounds([[Math.min(d.originLon,d.destinationLon),Math.min(d.originLat,d.destinationLat)],[Math.max(d.originLon,d.destinationLon),Math.max(d.originLat,d.destinationLat)]],{padding:90,duration:900,maxZoom:12.5});
  },[selectedId]);

  return <div className={`mapShell ${mapReady?"ready":""}`}><div ref={host} className="mapCanvas"/>{mapError&&<div className="mapError"><b>MAP OFFLINE</b><span>지도 타일 연결을 확인하세요. 배송 데이터 스트림은 계속 동작합니다.</span></div>}<div className="mapLegend"><span><i className="liveDot"/> LIVE VEHICLE</span><span><i className="routeDot"/> PLANNED ROUTE</span><span className="mapReady"><i/> {mapReady?"VECTOR MAP READY":"LOADING MAP"}</span></div></div>;
}

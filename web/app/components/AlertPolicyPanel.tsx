"use client";
import { FormEvent, useEffect, useMemo, useState } from "react";
import type { AlertPolicy, AlertPolicyAudit, Delivery } from "../types";

type Props = { policies:AlertPolicy[]; audits:AlertPolicyAudit[]; deliveries:Delivery[]; busy:boolean; onSave:(policy:PolicyInput)=>Promise<void>; onReset:(vehicleId:string)=>Promise<void>; onRestore:(auditId:string)=>Promise<void> };
export type PolicyInput = Pick<AlertPolicy,"vehicleId"|"deviationOpenMeters"|"deviationCloseMeters"|"criticalDeviationMeters"|"delayOpenSeconds"|"delayCloseSeconds"|"criticalDelaySeconds">;

const auditActionLabel: Record<AlertPolicyAudit["action"],string> = {UPSERT:"저장",RESET:"기본값 전환",RESTORE:"이력 복원"};

export default function AlertPolicyPanel({policies,audits,deliveries,busy,onSave,onReset,onRestore}:Props){
  const vehicles=useMemo(()=>Array.from(new Set(deliveries.map(item=>item.vehicleId))).sort(),[deliveries]);
  const [vehicleId,setVehicleId]=useState("*");
  const [auditQuery,setAuditQuery]=useState("");
  const [visibleAudits,setVisibleAudits]=useState(6);
  const fallback=policies.find(policy=>policy.vehicleId==="*");
  const selected=policies.find(policy=>policy.vehicleId===vehicleId)||fallback;
  const [draft,setDraft]=useState<PolicyInput>({vehicleId:"*",deviationOpenMeters:500,deviationCloseMeters:300,criticalDeviationMeters:1500,delayOpenSeconds:600,delayCloseSeconds:300,criticalDelaySeconds:1800});
  const filteredAudits=useMemo(()=>{
    const query=auditQuery.trim().toLowerCase();
    return query?audits.filter(audit=>[audit.vehicleId,audit.actor,auditActionLabel[audit.action]].some(value=>value.toLowerCase().includes(query))):audits;
  },[auditQuery,audits]);
  const shownAudits=filteredAudits.slice(0,visibleAudits);
  useEffect(()=>{if(selected)setDraft({vehicleId,deviationOpenMeters:selected.deviationOpenMeters,deviationCloseMeters:selected.deviationCloseMeters,
    criticalDeviationMeters:selected.criticalDeviationMeters,delayOpenSeconds:selected.delayOpenSeconds,delayCloseSeconds:selected.delayCloseSeconds,criticalDelaySeconds:selected.criticalDelaySeconds})},[selected,vehicleId]);
  useEffect(()=>setVisibleAudits(6),[auditQuery]);
  const setNumber=(field:keyof Omit<PolicyInput,"vehicleId">,value:string)=>setDraft(current=>({...current,[field]:Number(value)}));
  async function submit(event:FormEvent){event.preventDefault();await onSave({...draft,vehicleId});}
  const overridden=policies.some(policy=>policy.vehicleId===vehicleId);
  return <section className="policyBoard">
    <div className="policyHeader"><div><p className="eyebrow">경고 정책 관리</p><h2>차량별 경고 임계값</h2></div>
      <div className="policyScope"><label htmlFor="policyVehicle">적용 범위</label><select id="policyVehicle" value={vehicleId} onChange={event=>setVehicleId(event.target.value)}>
        <option value="*">전체 차량 기본값</option>{vehicles.map(vehicle=><option key={vehicle} value={vehicle}>{vehicle}</option>)}</select></div>
    </div>
    <div className="policyBody"><form onSubmit={submit}>
      <div className="policyMode"><b>{vehicleId==="*"?"전체 차량":vehicleId}</b><span className={overridden?"override":"inherited"}>{vehicleId==="*"?"기본 정책":overridden?"전용 정책":"기본값 상속"}</span></div>
      <fieldset><legend>경로 이탈 · 미터</legend>
        <label>해제<input type="number" min="0" required value={draft.deviationCloseMeters} onChange={event=>setNumber("deviationCloseMeters",event.target.value)}/></label>
        <label>경고<input type="number" min="1" required value={draft.deviationOpenMeters} onChange={event=>setNumber("deviationOpenMeters",event.target.value)}/></label>
        <label>긴급<input type="number" min="1" required value={draft.criticalDeviationMeters} onChange={event=>setNumber("criticalDeviationMeters",event.target.value)}/></label>
      </fieldset>
      <fieldset><legend>도착 지연 · 초</legend>
        <label>해제<input type="number" min="0" required value={draft.delayCloseSeconds} onChange={event=>setNumber("delayCloseSeconds",event.target.value)}/></label>
        <label>경고<input type="number" min="1" required value={draft.delayOpenSeconds} onChange={event=>setNumber("delayOpenSeconds",event.target.value)}/></label>
        <label>긴급<input type="number" min="1" required value={draft.criticalDelaySeconds} onChange={event=>setNumber("criticalDelaySeconds",event.target.value)}/></label>
      </fieldset>
      <p className="policyRule">임계값 순서: 해제 &lt; 경고 ≤ 긴급. 변경 사항은 다음 차량 위치 정보부터 적용됩니다.</p>
      <div className="policyActions"><button disabled={busy||!selected}>{busy?"정책 저장 중…":"변경 이력과 함께 저장"}</button>
        {vehicleId!=="*"&&overridden&&<button type="button" className="policyReset" disabled={busy} onClick={()=>onReset(vehicleId)}>전체 차량 기본값 사용</button>}</div>
    </form><aside><div className="policyAuditHeader"><h4>최근 정책 변경 이력</h4><label htmlFor="policyAuditSearch"><span>이력 검색</span><input id="policyAuditSearch" type="search" value={auditQuery} onChange={event=>setAuditQuery(event.target.value)} placeholder="차량 · 작업자 · 작업"/></label>{auditQuery&&<button type="button" onClick={()=>setAuditQuery("")}>초기화</button>}</div>{audits.length===0?<p className="policyEmpty">아직 운영자가 변경한 정책이 없습니다.</p>:filteredAudits.length===0?<p className="policyEmpty">검색 조건에 맞는 정책 변경 이력이 없습니다.</p>:shownAudits.map(audit=><div className="policyAudit" key={audit.id}>
      <span>{audit.vehicleId==="*"?"전체 차량":audit.vehicleId}</span><div><b>{auditActionLabel[audit.action]} · {audit.actor}</b><small>{new Date(audit.occurredAt).toLocaleString("ko-KR",{month:"short",day:"numeric",hour:"2-digit",minute:"2-digit"})}</small><em>경고 {audit.deviationOpenMeters}m · {Math.round(audit.delayOpenSeconds/60)}분</em></div>
      <button type="button" className="policyRestore" disabled={busy} onClick={()=>onRestore(audit.id)} aria-label={`${audit.vehicleId==="*"?"전체 차량":audit.vehicleId} 정책 이력 복원`}>이 값으로 복원</button></div>)}{filteredAudits.length>6&&<div className="policyAuditFooter"><span aria-live="polite">이력 {shownAudits.length} / {filteredAudits.length}건 표시</span>{shownAudits.length<filteredAudits.length?<button type="button" onClick={()=>setVisibleAudits(current=>Math.min(current+6,filteredAudits.length))}>다음 {Math.min(6,filteredAudits.length-shownAudits.length)}건 보기</button>:<button type="button" onClick={()=>setVisibleAudits(6)}>최근 6건만 보기</button>}</div>}</aside></div>
  </section>;
}

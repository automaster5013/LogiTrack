"use client";
import { FormEvent, useEffect, useMemo, useState } from "react";
import type { AlertPolicy, AlertPolicyAudit, Delivery } from "../types";

type Props = { policies:AlertPolicy[]; audits:AlertPolicyAudit[]; deliveries:Delivery[]; busy:boolean; onSave:(policy:PolicyInput)=>Promise<void>; onReset:(vehicleId:string)=>Promise<void>; onRestore:(auditId:string)=>Promise<void> };
export type PolicyInput = Pick<AlertPolicy,"vehicleId"|"deviationOpenMeters"|"deviationCloseMeters"|"criticalDeviationMeters"|"delayOpenSeconds"|"delayCloseSeconds"|"criticalDelaySeconds">;

export default function AlertPolicyPanel({policies,audits,deliveries,busy,onSave,onReset,onRestore}:Props){
  const vehicles=useMemo(()=>Array.from(new Set(deliveries.map(item=>item.vehicleId))).sort(),[deliveries]);
  const [vehicleId,setVehicleId]=useState("*");
  const fallback=policies.find(policy=>policy.vehicleId==="*");
  const selected=policies.find(policy=>policy.vehicleId===vehicleId)||fallback;
  const [draft,setDraft]=useState<PolicyInput>({vehicleId:"*",deviationOpenMeters:500,deviationCloseMeters:300,criticalDeviationMeters:1500,delayOpenSeconds:600,delayCloseSeconds:300,criticalDelaySeconds:1800});
  useEffect(()=>{if(selected)setDraft({vehicleId,deviationOpenMeters:selected.deviationOpenMeters,deviationCloseMeters:selected.deviationCloseMeters,
    criticalDeviationMeters:selected.criticalDeviationMeters,delayOpenSeconds:selected.delayOpenSeconds,delayCloseSeconds:selected.delayCloseSeconds,criticalDelaySeconds:selected.criticalDelaySeconds})},[selected,vehicleId]);
  const setNumber=(field:keyof Omit<PolicyInput,"vehicleId">,value:string)=>setDraft(current=>({...current,[field]:Number(value)}));
  async function submit(event:FormEvent){event.preventDefault();await onSave({...draft,vehicleId});}
  const overridden=policies.some(policy=>policy.vehicleId===vehicleId);
  return <section className="policyBoard">
    <div className="policyHeader"><div><p className="eyebrow">ALERT GOVERNANCE</p><h2>Vehicle threshold policies</h2></div>
      <div className="policyScope"><label htmlFor="policyVehicle">POLICY SCOPE</label><select id="policyVehicle" value={vehicleId} onChange={event=>setVehicleId(event.target.value)}>
        <option value="*">GLOBAL DEFAULT</option>{vehicles.map(vehicle=><option key={vehicle} value={vehicle}>{vehicle}</option>)}</select></div>
    </div>
    <div className="policyBody"><form onSubmit={submit}>
      <div className="policyMode"><b>{vehicleId==="*"?"GLOBAL DEFAULT":vehicleId}</b><span className={overridden?"override":"inherited"}>{overridden?"DEDICATED POLICY":"INHERITS GLOBAL"}</span></div>
      <fieldset><legend>ROUTE DEVIATION · METERS</legend>
        <label>CLOSE<input type="number" min="0" required value={draft.deviationCloseMeters} onChange={event=>setNumber("deviationCloseMeters",event.target.value)}/></label>
        <label>OPEN<input type="number" min="1" required value={draft.deviationOpenMeters} onChange={event=>setNumber("deviationOpenMeters",event.target.value)}/></label>
        <label>CRITICAL<input type="number" min="1" required value={draft.criticalDeviationMeters} onChange={event=>setNumber("criticalDeviationMeters",event.target.value)}/></label>
      </fieldset>
      <fieldset><legend>ETA DELAY · SECONDS</legend>
        <label>CLOSE<input type="number" min="0" required value={draft.delayCloseSeconds} onChange={event=>setNumber("delayCloseSeconds",event.target.value)}/></label>
        <label>OPEN<input type="number" min="1" required value={draft.delayOpenSeconds} onChange={event=>setNumber("delayOpenSeconds",event.target.value)}/></label>
        <label>CRITICAL<input type="number" min="1" required value={draft.criticalDelaySeconds} onChange={event=>setNumber("criticalDelaySeconds",event.target.value)}/></label>
      </fieldset>
      <p className="policyRule">Required order: CLOSE &lt; OPEN ≤ CRITICAL. Changes apply to the next telemetry event.</p>
      <div className="policyActions"><button disabled={busy||!selected}>{busy?"UPDATING POLICY…":"SAVE AUDITED POLICY"}</button>
        {vehicleId!=="*"&&overridden&&<button type="button" className="policyReset" disabled={busy} onClick={()=>onReset(vehicleId)}>RESET TO GLOBAL</button>}</div>
    </form><aside><h4>RECENT POLICY AUDIT</h4>{audits.length===0?<p className="policyEmpty">No operator changes yet.</p>:audits.slice(0,6).map(audit=><div className="policyAudit" key={audit.id}>
      <span>{audit.vehicleId==="*"?"GLOBAL":audit.vehicleId}</span><div><b>{audit.action} · {audit.actor}</b><small>{new Date(audit.occurredAt).toLocaleString("ko-KR",{month:"short",day:"numeric",hour:"2-digit",minute:"2-digit"})}</small><em>OPEN {audit.deviationOpenMeters}m · {Math.round(audit.delayOpenSeconds/60)}min</em></div>
      <button type="button" className="policyRestore" disabled={busy} onClick={()=>onRestore(audit.id)}>RESTORE</button></div>)}</aside></div>
  </section>;
}

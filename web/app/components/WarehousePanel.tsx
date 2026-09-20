import { useEffect, useState } from "react";
import type { LedgerEntry, WarehouseStock, WarehouseTask } from "../types";

type Props = {
  stocks: WarehouseStock[];
  ledger: LedgerEntry[];
  tasks: WarehouseTask[];
  busy: boolean;
  onReceive: () => void;
  onPickAndDispatch: () => void;
};

const transactionLabel: Record<LedgerEntry["transactionType"],string> = {
  RECEIPT: "입고",
  PICK: "피킹",
  DISPATCH: "출고"
};

export default function WarehousePanel({stocks,ledger,tasks,busy,onReceive,onPickAndDispatch}:Props){
  const [visibleStocks,setVisibleStocks]=useState(8);
  const [visibleLedger,setVisibleLedger]=useState(7);
  const shownStocks=stocks.slice(0,visibleStocks);
  const shownLedger=ledger.slice(0,visibleLedger);

  useEffect(()=>setVisibleStocks(current=>Math.max(8,Math.min(current,Math.max(stocks.length,8)))),[stocks.length]);
  useEffect(()=>setVisibleLedger(current=>Math.max(7,Math.min(current,Math.max(ledger.length,7)))),[ledger.length]);

  return <section className="warehouseBoard"><div className="warehouseHeader"><div><p className="eyebrow">창고 / 재고</p><h2>재고 관리</h2></div><div className="warehouseActions"><button disabled={busy} onClick={onReceive} aria-label="시연 재고 10개 입고">{busy?"처리 중…":"+ 재고 10개 입고"}</button><button disabled={busy} onClick={onPickAndDispatch} aria-label="재고 4개 피킹 및 출고">{busy?"처리 중…":"4개 피킹·출고"}</button></div></div>
    <div className="warehouseGrid"><div className="stockPane"><h4>가용 재고</h4>{stocks.length===0?<p className="warehouseEmpty">아직 등록된 재고가 없습니다. 상단의 입고 버튼으로 시연 재고를 추가할 수 있습니다.</p>:<><div className="stockTable"><div className="stockRow head"><span>창고 / SKU</span><span>현재고</span><span>예약</span><span>가용</span></div>{shownStocks.map(stock=><div className="stockRow" key={stock.id}><span><b>{stock.warehouseId}</b><small>{stock.sku}</small></span><strong>{stock.onHand}</strong><strong>{stock.reserved}</strong><strong className="available">{stock.available}</strong></div>)}</div>{stocks.length>8&&<ListFooter label="재고" shown={shownStocks.length} total={stocks.length} step={8} onChange={setVisibleStocks}/>}</>}</div>
      <div className="ledgerPane"><h4>최근 재고 변동</h4>{ledger.length===0?<p className="warehouseEmpty">입고나 출고가 처리되면 재고 변동 내역이 여기에 표시됩니다.</p>:<>{shownLedger.map(entry=><div className="ledgerRow" key={entry.id}><span className={`movement ${entry.transactionType.toLowerCase()}`}>{transactionLabel[entry.transactionType]}</span><span><b>{entry.sku}</b><small>{entry.warehouseId}</small></span><span className="delta" aria-label={`재고 변동 ${entry.onHandDelta||entry.reservedDelta}`}>{entry.onHandDelta>0?`+${entry.onHandDelta}`:entry.onHandDelta||`예약 +${entry.reservedDelta}`}</span></div>)}{ledger.length>7&&<ListFooter label="원장" shown={shownLedger.length} total={ledger.length} step={7} onChange={setVisibleLedger}/>}</>}</div></div>
    <div className="taskStrip" aria-label="출고 작업 요약"><span>출고 대기 {tasks.filter(task=>task.status==="PICKED").length}건</span><span>출고 완료 {tasks.filter(task=>task.status==="DISPATCHED").length}건</span><span>재고 변동 {ledger.length}건</span></div>
  </section>;
}

function ListFooter({label,shown,total,step,onChange}:{label:string;shown:number;total:number;step:number;onChange:(count:number)=>void}){
  const remaining=total-shown;
  return <div className="warehouseListFooter"><span aria-live="polite">{label} {shown} / {total}건 표시</span>{remaining>0?<button type="button" onClick={()=>onChange(Math.min(shown+step,total))}>다음 {Math.min(step,remaining)}건 보기</button>:<button type="button" onClick={()=>onChange(step)}>최근 {step}건만 보기</button>}</div>;
}

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

export default function WarehousePanel({stocks,ledger,tasks,busy,onReceive,onPickAndDispatch}:Props){
  const [visibleStocks,setVisibleStocks]=useState(8);
  const [visibleLedger,setVisibleLedger]=useState(7);
  const shownStocks=stocks.slice(0,visibleStocks);
  const shownLedger=ledger.slice(0,visibleLedger);

  useEffect(()=>setVisibleStocks(current=>Math.max(8,Math.min(current,Math.max(stocks.length,8)))),[stocks.length]);
  useEffect(()=>setVisibleLedger(current=>Math.max(7,Math.min(current,Math.max(ledger.length,7)))),[ledger.length]);

  return <section className="warehouseBoard"><div className="warehouseHeader"><div><p className="eyebrow">WAREHOUSE / INVENTORY</p><h2>Stock control</h2></div><div className="warehouseActions"><button disabled={busy} onClick={onReceive}>+ RECEIVE 10</button><button disabled={busy} onClick={onPickAndDispatch}>PICK & DISPATCH 4</button></div></div>
    <div className="warehouseGrid"><div className="stockPane"><h4>AVAILABLE STOCK</h4>{stocks.length===0?<p className="warehouseEmpty">No inventory yet. Receive demo stock to begin.</p>:<><div className="stockTable"><div className="stockRow head"><span>LOCATION / SKU</span><span>ON HAND</span><span>RESERVED</span><span>AVAILABLE</span></div>{shownStocks.map(stock=><div className="stockRow" key={stock.id}><span><b>{stock.warehouseId}</b><small>{stock.sku}</small></span><strong>{stock.onHand}</strong><strong>{stock.reserved}</strong><strong className="available">{stock.available}</strong></div>)}</div>{stocks.length>8&&<ListFooter label="재고" shown={shownStocks.length} total={stocks.length} step={8} onChange={setVisibleStocks}/>}</>}</div>
      <div className="ledgerPane"><h4>RECENT LEDGER</h4>{ledger.length===0?<p className="warehouseEmpty">Inventory movements will appear here.</p>:<>{shownLedger.map(entry=><div className="ledgerRow" key={entry.id}><span className={`movement ${entry.transactionType.toLowerCase()}`}>{entry.transactionType}</span><span><b>{entry.sku}</b><small>{entry.warehouseId}</small></span><span className="delta">{entry.onHandDelta>0?`+${entry.onHandDelta}`:entry.onHandDelta||`R +${entry.reservedDelta}`}</span></div>)}{ledger.length>7&&<ListFooter label="원장" shown={shownLedger.length} total={ledger.length} step={7} onChange={setVisibleLedger}/>}</>}</div></div>
    <div className="taskStrip"><span>{tasks.filter(task=>task.status==="PICKED").length} awaiting dispatch</span><span>{tasks.filter(task=>task.status==="DISPATCHED").length} dispatched</span><span>{ledger.length} ledger movements loaded</span></div>
  </section>;
}

function ListFooter({label,shown,total,step,onChange}:{label:string;shown:number;total:number;step:number;onChange:(count:number)=>void}){
  const remaining=total-shown;
  return <div className="warehouseListFooter"><span aria-live="polite">{label} {shown} / {total}건 표시</span>{remaining>0?<button type="button" onClick={()=>onChange(Math.min(shown+step,total))}>다음 {Math.min(step,remaining)}건 보기</button>:<button type="button" onClick={()=>onChange(step)}>최근 {step}건만 보기</button>}</div>;
}

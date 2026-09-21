import { useEffect, useMemo, useState } from "react";
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
const taskStatusLabel: Record<WarehouseTask["status"],string> = {RECEIVED:"입고 완료",PICKED:"출고 대기",DISPATCHED:"출고 완료"};

export default function WarehousePanel({stocks,ledger,tasks,busy,onReceive,onPickAndDispatch}:Props){
  const [stockScope,setStockScope]=useState<"ALL"|"UNAVAILABLE">("ALL");
  const [stockQuery,setStockQuery]=useState("");
  const [ledgerScope,setLedgerScope]=useState<"ALL"|LedgerEntry["transactionType"]>("ALL");
  const [ledgerQuery,setLedgerQuery]=useState("");
  const [visibleStocks,setVisibleStocks]=useState(8);
  const [visibleLedger,setVisibleLedger]=useState(7);
  const [taskScope,setTaskScope]=useState<"ALL"|WarehouseTask["status"]>("ALL");
  const [taskQuery,setTaskQuery]=useState("");
  const [visibleTasks,setVisibleTasks]=useState(6);
  const unavailableStocks=stocks.filter(stock=>stock.available<=0).length;
  const receiptEntries=ledger.filter(entry=>entry.transactionType==="RECEIPT").length;
  const pickEntries=ledger.filter(entry=>entry.transactionType==="PICK").length;
  const dispatchEntries=ledger.filter(entry=>entry.transactionType==="DISPATCH").length;
  const receivedTasks=tasks.filter(task=>task.status==="RECEIVED").length;
  const pickedTasks=tasks.filter(task=>task.status==="PICKED").length;
  const dispatchedTasks=tasks.filter(task=>task.status==="DISPATCHED").length;
  const filteredStocks=useMemo(()=>{
    const query=stockQuery.trim().toLowerCase();
    return stocks.filter(stock=>(stockScope==="ALL"||stock.available<=0)&&(!query||[stock.warehouseId,stock.sku].some(value=>value.toLowerCase().includes(query))));
  },[stocks,stockQuery,stockScope]);
  const filteredLedger=useMemo(()=>{
    const query=ledgerQuery.trim().toLowerCase();
    return ledger.filter(entry=>(ledgerScope==="ALL"||entry.transactionType===ledgerScope)&&(!query||[entry.warehouseId,entry.sku].some(value=>value.toLowerCase().includes(query))));
  },[ledger,ledgerQuery,ledgerScope]);
  const shownStocks=filteredStocks.slice(0,visibleStocks);
  const shownLedger=filteredLedger.slice(0,visibleLedger);
  const filteredTasks=useMemo(()=>{const query=taskQuery.trim().toLowerCase();return tasks.filter(task=>(taskScope==="ALL"||task.status===taskScope)&&(!query||[task.referenceNumber,task.warehouseId,task.sku].some(value=>value.toLowerCase().includes(query))))},[taskQuery,taskScope,tasks]);
  const shownTasks=filteredTasks.slice(0,visibleTasks);

  useEffect(()=>setVisibleStocks(8),[stockQuery,stockScope]);
  useEffect(()=>setVisibleLedger(7),[ledgerQuery,ledgerScope]);
  useEffect(()=>setVisibleStocks(current=>Math.max(8,Math.min(current,Math.max(stocks.length,8)))),[stocks.length]);
  useEffect(()=>setVisibleLedger(current=>Math.max(7,Math.min(current,Math.max(ledger.length,7)))),[ledger.length]);
  useEffect(()=>setVisibleTasks(6),[taskQuery,taskScope]);
  useEffect(()=>setVisibleTasks(current=>Math.max(6,Math.min(current,Math.max(filteredTasks.length,6)))),[filteredTasks.length]);

  return <section className="warehouseBoard"><div className="warehouseHeader"><div><p className="eyebrow">창고 / 재고</p><h2>재고 관리</h2></div><div className="warehouseActions"><button disabled={busy} onClick={onReceive} aria-label="시연 재고 10개 입고">{busy?"처리 중…":"+ 재고 10개 입고"}</button><button disabled={busy} onClick={onPickAndDispatch} aria-label="재고 4개 피킹 및 출고">{busy?"처리 중…":"4개 피킹·출고"}</button></div></div>
    <div className="warehouseGrid"><div className="stockPane"><div className="stockPaneHeader"><h4>가용 재고</h4><div className="stockScope" aria-label="재고 표시 범위"><button type="button" aria-pressed={stockScope==="ALL"} onClick={()=>setStockScope("ALL")}>전체 {stocks.length}</button><button type="button" aria-pressed={stockScope==="UNAVAILABLE"} onClick={()=>setStockScope("UNAVAILABLE")}>가용 0 {unavailableStocks}</button></div><label className="stockSearch" htmlFor="stockSearch"><span>재고 검색</span><input id="stockSearch" type="search" value={stockQuery} onChange={event=>setStockQuery(event.target.value)} placeholder="창고 · SKU"/></label>{stockQuery&&<button type="button" className="stockSearchClear" onClick={()=>setStockQuery("")}>초기화</button>}</div>{stocks.length===0?<p className="warehouseEmpty">아직 등록된 재고가 없습니다. 상단의 입고 버튼으로 시연 재고를 추가할 수 있습니다.</p>:filteredStocks.length===0?<p className="warehouseEmpty">현재 범위와 검색 조건에 맞는 재고가 없습니다.</p>:<><div className="stockTable"><div className="stockRow head"><span>창고 / SKU</span><span>현재고</span><span>예약</span><span>가용</span></div>{shownStocks.map(stock=><div className="stockRow" key={stock.id}><span><b>{stock.warehouseId}</b><small>{stock.sku}</small><small><time dateTime={stock.updatedAt}>마지막 갱신 {new Date(stock.updatedAt).toLocaleString("ko-KR")}</time></small></span><strong>{stock.onHand}</strong><strong>{stock.reserved}</strong><strong className="available">{stock.available}</strong></div>)}</div>{filteredStocks.length>8&&<ListFooter label="재고" shown={shownStocks.length} total={filteredStocks.length} step={8} onChange={setVisibleStocks}/>}</>}</div>
      <div className="ledgerPane"><div className="ledgerPaneHeader"><h4>최근 재고 변동</h4><label htmlFor="ledgerScope"><span>유형</span><select id="ledgerScope" value={ledgerScope} onChange={event=>setLedgerScope(event.target.value as "ALL"|LedgerEntry["transactionType"])}><option value="ALL">전체 {ledger.length}</option><option value="RECEIPT">입고 {receiptEntries}</option><option value="PICK">피킹 {pickEntries}</option><option value="DISPATCH">출고 {dispatchEntries}</option></select></label><label htmlFor="ledgerSearch"><span>원장 검색</span><input id="ledgerSearch" type="search" value={ledgerQuery} onChange={event=>setLedgerQuery(event.target.value)} placeholder="창고 · SKU"/></label>{ledgerQuery&&<button type="button" onClick={()=>setLedgerQuery("")}>초기화</button>}</div>{ledger.length===0?<p className="warehouseEmpty">입고나 출고가 처리되면 재고 변동 내역이 여기에 표시됩니다.</p>:filteredLedger.length===0?<p className="warehouseEmpty">현재 유형과 검색 조건에 맞는 재고 변동이 없습니다.</p>:<>{shownLedger.map(entry=><div className="ledgerRow" key={entry.id}><span className={`movement ${entry.transactionType.toLowerCase()}`}>{transactionLabel[entry.transactionType]}</span><span><b>{entry.sku}</b><small>{entry.warehouseId}</small><small><time dateTime={entry.occurredAt}>{new Date(entry.occurredAt).toLocaleString("ko-KR")}</time> · 반영 후 현재고 {entry.onHandAfter} / 예약 {entry.reservedAfter}</small></span><span className="delta" aria-label={`재고 변동 ${entry.onHandDelta||entry.reservedDelta}`}>{entry.onHandDelta>0?`+${entry.onHandDelta}`:entry.onHandDelta||`예약 +${entry.reservedDelta}`}</span></div>)}{filteredLedger.length>7&&<ListFooter label="원장" shown={shownLedger.length} total={filteredLedger.length} step={7} onChange={setVisibleLedger}/>}</>}</div></div>
    <section className="warehouseTasks" aria-labelledby="warehouseTasksTitle"><div className="warehouseTaskHeader"><div><h3 id="warehouseTasksTitle">최근 창고 작업</h3><span>입고 완료 {receivedTasks}건 · 출고 대기 {pickedTasks}건 · 출고 완료 {dispatchedTasks}건</span></div><label htmlFor="warehouseTaskScope"><span>상태</span><select id="warehouseTaskScope" value={taskScope} onChange={event=>setTaskScope(event.target.value as "ALL"|WarehouseTask["status"])}><option value="ALL">전체 {tasks.length}</option><option value="RECEIVED">입고 완료 {receivedTasks}</option><option value="PICKED">출고 대기 {pickedTasks}</option><option value="DISPATCHED">출고 완료 {dispatchedTasks}</option></select></label><label htmlFor="warehouseTaskSearch"><span>작업 검색</span><input id="warehouseTaskSearch" type="search" value={taskQuery} onChange={event=>setTaskQuery(event.target.value)} placeholder="참조번호 · 창고 · SKU"/></label>{(taskQuery||taskScope!=="ALL")&&<button type="button" onClick={()=>{setTaskQuery("");setTaskScope("ALL")}}>초기화</button>}</div>
      {tasks.length===0?<p className="warehouseEmpty">입고 또는 출고 작업이 처리되면 여기에 표시됩니다.</p>:filteredTasks.length===0?<p className="warehouseEmpty">현재 상태와 검색 조건에 맞는 창고 작업이 없습니다.</p>:<><div className="warehouseTaskList">{shownTasks.map(task=><article key={task.id}><span className={`taskState ${task.status.toLowerCase()}`}>{taskStatusLabel[task.status]}</span><div><b>{task.referenceNumber}</b><small>{task.warehouseId} · {task.sku}</small></div><strong>{task.quantity}개</strong><time dateTime={task.createdAt}>{new Date(task.createdAt).toLocaleString("ko-KR")}</time></article>)}</div>{filteredTasks.length>6&&<ListFooter label="작업" shown={shownTasks.length} total={filteredTasks.length} step={6} onChange={setVisibleTasks}/>}</>}
    </section>
  </section>;
}

function ListFooter({label,shown,total,step,onChange}:{label:string;shown:number;total:number;step:number;onChange:(count:number)=>void}){
  const remaining=total-shown;
  return <div className="warehouseListFooter"><span aria-live="polite">{label} {shown} / {total}건 표시</span>{remaining>0?<button type="button" onClick={()=>onChange(Math.min(shown+step,total))}>다음 {Math.min(step,remaining)}건 보기</button>:<button type="button" onClick={()=>onChange(step)}>최근 {step}건만 보기</button>}</div>;
}

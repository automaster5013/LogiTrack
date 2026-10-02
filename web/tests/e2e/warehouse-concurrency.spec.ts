import { expect, test, type Page } from "@playwright/test";
import type { WarehouseTask } from "../../app/types";

const now = "2026-09-28T03:00:00Z";
const outboundTask: WarehouseTask = {
  id:"00000000-0000-4000-8000-000000000301",
  taskType:"OUTBOUND",
  status:"PICKED",
  referenceNumber:"OUT-000301",
  warehouseId:"SEOUL-HUB-A",
  sku:"COLD-BOX-01",
  quantity:4,
  createdAt:now,
  updatedAt:now,
};

type WarehouseFixture = { receiptFailuresBeforeSuccess?:number; pickFailuresBeforeSuccess?:number; dispatchFailuresBeforeSuccess?:number; disconnectAfterPick?:boolean };

async function mockWarehouse(page:Page, fixture:WarehouseFixture={}) {
  const receiptRequests:string[]=[];
  const receiptIdempotencyKeys:string[]=[];
  const outboundRequests:string[]=[];
  const outboundIdempotencyKeys:string[]=[];
  const dispatchRequests:string[]=[];
  await page.route("**/api/**", async route=>{
    const request=route.request();
    const url=new URL(request.url());
    const common={headers:{"Access-Control-Allow-Origin":"*","Content-Type":"application/json"}};
    if(url.pathname==="/api/warehouse/receipts"&&request.method()==="POST"){
      receiptRequests.push(request.postDataJSON().referenceNumber);
      receiptIdempotencyKeys.push(request.headers()["idempotency-key"]);
      await new Promise(resolve=>setTimeout(resolve,1_000));
      if(receiptRequests.length<=(fixture.receiptFailuresBeforeSuccess||0))return route.fulfill({status:503,...common,json:{error:"temporarily_unavailable"}});
      return route.fulfill({...common,json:{...outboundTask,id:"00000000-0000-4000-8000-000000000302",taskType:"INBOUND",status:"RECEIVED",referenceNumber:receiptRequests.at(-1)}});
    }
    if(url.pathname==="/api/warehouse/outbounds"&&request.method()==="POST"){
      outboundRequests.push(request.postDataJSON().referenceNumber);
      outboundIdempotencyKeys.push(request.headers()["idempotency-key"]);
      await new Promise(resolve=>setTimeout(resolve,500));
      if(outboundRequests.length<=(fixture.pickFailuresBeforeSuccess||0))return route.fulfill({status:503,...common,json:{error:"temporarily_unavailable"}});
      if(fixture.disconnectAfterPick)await page.evaluate(()=>{
        Object.defineProperty(Navigator.prototype,"onLine",{configurable:true,get:()=>false});
        window.dispatchEvent(new Event("offline"));
      });
      return route.fulfill({...common,json:outboundTask});
    }
    if(url.pathname===`/api/warehouse/outbounds/${outboundTask.id}/dispatch`&&request.method()==="POST"){
      dispatchRequests.push(outboundTask.id);
      await new Promise(resolve=>setTimeout(resolve,1_000));
      if(dispatchRequests.length<=(fixture.dispatchFailuresBeforeSuccess||0))return route.fulfill({status:503,...common,json:{error:"temporarily_unavailable"}});
      return route.fulfill({...common,json:{...outboundTask,status:"DISPATCHED"}});
    }
    if(["/api/warehouse/stock/page","/api/warehouse/tasks/page","/api/warehouse/ledger/page","/api/deliveries/page","/api/alerts/page","/api/orders/page"].includes(url.pathname))return route.fulfill({...common,json:{items:[],page:0,size:100,totalElements:0,hasMore:false}});
    if(["/api/routes","/api/telemetry/points","/api/reports/daily-kpis"].includes(url.pathname))return route.fulfill({...common,json:[]});
    if(url.pathname==="/api/stream/deliveries")return route.fulfill({status:200,contentType:"text/event-stream",body:"event: connected\ndata: {}\n\n",headers:{"Access-Control-Allow-Origin":"*"}});
    return route.fulfill({status:404,...common,json:{error:"not_found"}});
  });
  return {receiptRequests,receiptIdempotencyKeys,outboundRequests,outboundIdempotencyKeys,dispatchRequests};
}

test("sends one warehouse receipt for immediate repeated input",async({page})=>{
  const {receiptRequests}=await mockWarehouse(page);
  await page.goto("/console#warehouse");
  const receive=page.getByRole("button",{name:"시연 재고 10개 입고"});
  await expect(receive).toBeVisible();
  await receive.evaluate(button=>{const target=button as HTMLButtonElement;target.click();target.click()});
  await expect(receive).toBeDisabled();
  await expect(receive).toBeEnabled({timeout:1_500});
  expect(receiptRequests).toHaveLength(1);
});

test("pauses warehouse mutations while offline and restores them online",async({page,context})=>{
  const {receiptRequests,outboundRequests,dispatchRequests}=await mockWarehouse(page);
  await page.goto("/console#warehouse");
  const receive=page.getByRole("button",{name:"시연 재고 10개 입고"});
  const dispatch=page.getByRole("button",{name:"재고 4개 피킹 및 출고"});

  await context.setOffline(true);
  await expect(receive).toHaveText("네트워크 연결 대기 중…");
  await expect(receive).toBeDisabled();
  await expect(dispatch).toHaveText("네트워크 연결 대기 중…");
  await expect(dispatch).toBeDisabled();
  expect(receiptRequests).toHaveLength(0);
  expect(outboundRequests).toHaveLength(0);
  expect(dispatchRequests).toHaveLength(0);

  await context.setOffline(false);
  await expect(receive).toHaveText("+ 재고 10개 입고");
  await expect(receive).toBeEnabled();
  await expect(dispatch).toHaveText("4개 피킹·출고");
  await expect(dispatch).toBeEnabled();
  await receive.click();
  await expect(receive).toBeEnabled({timeout:1_500});
  expect(receiptRequests).toHaveLength(1);
});

test("keeps a receipt error visible until receipt retry succeeds",async({page})=>{
  const {receiptRequests,receiptIdempotencyKeys}=await mockWarehouse(page,{receiptFailuresBeforeSuccess:1});
  await page.goto("/console#warehouse");
  const receive=page.getByRole("button",{name:"시연 재고 10개 입고"});
  const error=page.getByText("입고 처리에 실패했습니다.");
  await receive.click();
  await expect(error).toBeVisible({timeout:1_500});
  await receive.click();
  await expect(error).toBeVisible();
  await expect(receive).toBeEnabled({timeout:1_500});
  await expect(error).toBeHidden();
  expect(receiptRequests).toHaveLength(2);
  expect(new Set(receiptRequests).size).toBe(1);
  expect(new Set(receiptIdempotencyKeys).size).toBe(1);
  await receive.click();
  await expect(receive).toBeEnabled({timeout:1_500});
  expect(receiptRequests).toHaveLength(3);
  expect(receiptRequests[2]).toMatch(/^ASN-[0-9A-F]{12}$/);
  expect(receiptRequests[2]).not.toBe(receiptRequests[1]);
  expect(receiptIdempotencyKeys[2]).not.toBe(receiptIdempotencyKeys[1]);
});

test("sends one pick and dispatch flow for immediate repeated input",async({page})=>{
  const {outboundRequests,dispatchRequests}=await mockWarehouse(page);
  await page.goto("/console#warehouse");
  const dispatch=page.getByRole("button",{name:"재고 4개 피킹 및 출고"});
  await expect(dispatch).toBeVisible();
  await dispatch.evaluate(button=>{const target=button as HTMLButtonElement;target.click();target.click()});
  await expect(dispatch).toBeDisabled();
  await expect(dispatch).toBeEnabled({timeout:2_000});
  expect(outboundRequests).toHaveLength(1);
  expect(dispatchRequests).toEqual([outboundTask.id]);
});

test("reuses the pick identity after an ambiguous failure and resets it after success",async({page})=>{
  const {outboundRequests,outboundIdempotencyKeys,dispatchRequests}=await mockWarehouse(page,{pickFailuresBeforeSuccess:1});
  await page.goto("/console#warehouse");
  const dispatch=page.getByRole("button",{name:"재고 4개 피킹 및 출고"});
  const error=page.getByText("출고 처리에 실패했습니다. 먼저 재고를 입고해 주세요.");

  await dispatch.click();
  await expect(error).toBeVisible({timeout:1_500});
  await dispatch.click();
  await expect(dispatch).toBeEnabled({timeout:2_000});
  await expect(error).toBeHidden();
  expect(outboundRequests).toHaveLength(2);
  expect(new Set(outboundRequests).size).toBe(1);
  expect(new Set(outboundIdempotencyKeys).size).toBe(1);
  expect(dispatchRequests).toEqual([outboundTask.id]);

  await dispatch.click();
  await expect(dispatch).toBeEnabled({timeout:2_000});
  expect(outboundRequests).toHaveLength(3);
  expect(outboundRequests[2]).toMatch(/^OUT-[0-9A-F]{12}$/);
  expect(outboundRequests[2]).not.toBe(outboundRequests[1]);
  expect(outboundIdempotencyKeys[2]).not.toBe(outboundIdempotencyKeys[1]);
  expect(dispatchRequests).toEqual([outboundTask.id,outboundTask.id]);
});

test("retries dispatch without creating another pick and preserves its error",async({page})=>{
  const {outboundRequests,dispatchRequests}=await mockWarehouse(page,{dispatchFailuresBeforeSuccess:1});
  await page.goto("/console#warehouse");
  const dispatch=page.getByRole("button",{name:"재고 4개 피킹 및 출고"});
  const error=page.getByText("출고 처리에 실패했습니다. 먼저 재고를 입고해 주세요.");
  await dispatch.click();
  await expect(error).toBeVisible({timeout:2_000});
  await dispatch.click();
  await expect(error).toBeVisible();
  await expect(dispatch).toBeEnabled({timeout:1_500});
  await expect(error).toBeHidden();
  expect(outboundRequests).toHaveLength(1);
  expect(dispatchRequests).toEqual([outboundTask.id,outboundTask.id]);
});

test("keeps the picked task and pauses dispatch when connectivity drops between steps",async({page})=>{
  const {outboundRequests,dispatchRequests}=await mockWarehouse(page,{disconnectAfterPick:true});
  await page.goto("/console#warehouse");
  const dispatch=page.getByRole("button",{name:"재고 4개 피킹 및 출고"});
  const error=page.getByText("출고 처리에 실패했습니다. 먼저 재고를 입고해 주세요.");

  await dispatch.click();
  await expect(dispatch).toHaveText("네트워크 연결 대기 중…");
  await expect(error).toBeHidden();
  expect(outboundRequests).toHaveLength(1);
  expect(dispatchRequests).toHaveLength(0);

  await page.evaluate(()=>{
    Object.defineProperty(Navigator.prototype,"onLine",{configurable:true,get:()=>true});
    window.dispatchEvent(new Event("online"));
  });
  await expect(dispatch).toHaveText("4개 피킹·출고");
  await dispatch.click();
  await expect(dispatch).toBeEnabled({timeout:1_500});
  expect(outboundRequests).toHaveLength(1);
  expect(dispatchRequests).toEqual([outboundTask.id]);
});

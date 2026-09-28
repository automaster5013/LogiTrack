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

type WarehouseFixture = { receiptFailuresBeforeSuccess?:number; dispatchFailuresBeforeSuccess?:number };

async function mockWarehouse(page:Page, fixture:WarehouseFixture={}) {
  const receiptRequests:string[]=[];
  const outboundRequests:string[]=[];
  const dispatchRequests:string[]=[];
  await page.route("**/api/**", async route=>{
    const request=route.request();
    const url=new URL(request.url());
    const common={headers:{"Access-Control-Allow-Origin":"*","Content-Type":"application/json"}};
    if(url.pathname==="/api/warehouse/receipts"&&request.method()==="POST"){
      receiptRequests.push(request.postDataJSON().referenceNumber);
      await new Promise(resolve=>setTimeout(resolve,1_000));
      if(receiptRequests.length<=(fixture.receiptFailuresBeforeSuccess||0))return route.fulfill({status:503,...common,json:{error:"temporarily_unavailable"}});
      return route.fulfill({...common,json:{...outboundTask,id:"00000000-0000-4000-8000-000000000302",taskType:"INBOUND",status:"RECEIVED",referenceNumber:receiptRequests.at(-1)}});
    }
    if(url.pathname==="/api/warehouse/outbounds"&&request.method()==="POST"){
      outboundRequests.push(request.postDataJSON().referenceNumber);
      await new Promise(resolve=>setTimeout(resolve,500));
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
  return {receiptRequests,outboundRequests,dispatchRequests};
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

test("keeps a receipt error visible until receipt retry succeeds",async({page})=>{
  const {receiptRequests}=await mockWarehouse(page,{receiptFailuresBeforeSuccess:1});
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

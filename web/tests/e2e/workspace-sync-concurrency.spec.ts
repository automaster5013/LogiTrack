import { expect, test, type Page } from "@playwright/test";
import type { DeadLetterEvent } from "../../app/types";

type OverviewFixture={deliveryFailuresBeforeSuccess?:number};

async function mockOverview(page:Page,fixture:OverviewFixture={}){
  const deliveryRequests:number[]=[];
  const alertRequests:number[]=[];
  const kpiRequests:number[]=[];
  await page.route("**/api/**",async route=>{
    const request=route.request();
    const url=new URL(request.url());
    const common={headers:{"Access-Control-Allow-Origin":"*","Content-Type":"application/json"}};
    if(url.pathname==="/api/deliveries/page"){
      deliveryRequests.push(deliveryRequests.length+1);
      await new Promise(resolve=>setTimeout(resolve,deliveryRequests.length===1?100:1_000));
      if(deliveryRequests.length<=(fixture.deliveryFailuresBeforeSuccess||0))return route.fulfill({status:503,...common,json:{error:"temporarily_unavailable"}});
      return route.fulfill({...common,json:{items:[],page:0,size:100,totalElements:0,hasMore:false}});
    }
    if(url.pathname==="/api/alerts/page"){
      alertRequests.push(alertRequests.length+1);
      await new Promise(resolve=>setTimeout(resolve,100));
      return route.fulfill({...common,json:{items:[],page:0,size:100,totalElements:0,hasMore:false}});
    }
    if(url.pathname==="/api/reports/daily-kpis"){
      kpiRequests.push(kpiRequests.length+1);
      await new Promise(resolve=>setTimeout(resolve,100));
      return route.fulfill({...common,json:[]});
    }
    if(["/api/routes","/api/telemetry/points"].includes(url.pathname))return route.fulfill({...common,json:[]});
    if(url.pathname==="/api/stream/deliveries")return route.fulfill({status:200,contentType:"text/event-stream",body:"event: connected\ndata: {}\n\n",headers:{"Access-Control-Allow-Origin":"*"}});
    return route.fulfill({status:404,...common,json:{error:"not_found"}});
  });
  return {deliveryRequests,alertRequests,kpiRequests};
}

test("sends one workspace refresh for immediate repeated input",async({page})=>{
  const requests=await mockOverview(page);
  await page.goto("/console#overview");
  await expect(page.getByText(/최근 동기화/)).toBeVisible();
  requests.deliveryRequests.length=0;
  requests.alertRequests.length=0;
  requests.kpiRequests.length=0;
  const refresh=page.locator(".workspaceTools button").first();
  await refresh.evaluate(button=>{const target=button as HTMLButtonElement;target.click();target.click()});
  await expect(refresh).toBeDisabled();
  await expect(refresh).toBeEnabled({timeout:1_500});
  expect(requests.deliveryRequests).toHaveLength(1);
  expect(requests.alertRequests).toHaveLength(1);
  expect(requests.kpiRequests).toHaveLength(1);
});

test("keeps a workspace error visible until refresh succeeds",async({page})=>{
  const {deliveryRequests}=await mockOverview(page,{deliveryFailuresBeforeSuccess:1});
  await page.goto("/console#overview");
  const error=page.getByText("API에 연결할 수 없습니다.");
  await expect(error).toBeVisible();
  const retry=page.locator(".errorActions button").first();
  await retry.click();
  await expect(error).toBeVisible();
  await expect(error).toBeHidden({timeout:3_000});
  expect(deliveryRequests).toHaveLength(2);
});

const failedAt="2026-09-28T05:00:00Z";
const deadLetters:DeadLetterEvent[]=[1,2].map(index=>({id:`00000000-0000-4000-8000-00000000040${index}`,originalTopic:"telemetry.events.DLT",messageKey:`delivery-${index}`,payload:"{}",traceId:`trace-page-${index}`,exceptionMessage:"invalid telemetry",dlqPartition:0,dlqOffset:index,status:"PENDING",failedAt}));

async function mockRecoveryPages(page:Page){
  const requestedPages:number[]=[];
  await page.route("**/api/**",async route=>{
    const url=new URL(route.request().url());
    const common={headers:{"Access-Control-Allow-Origin":"*","Content-Type":"application/json"}};
    if(url.pathname==="/api/operations/dlq-page"){
      const requestedPage=Number(url.searchParams.get("page")||0);
      const size=Number(url.searchParams.get("size")||100);
      if(size!==1)requestedPages.push(requestedPage);
      if(requestedPage===1)await new Promise(resolve=>setTimeout(resolve,1_000));
      const items=size===1?deadLetters.slice(0,1):[deadLetters[requestedPage]||deadLetters[0]];
      return route.fulfill({...common,json:{items,page:requestedPage,size,totalElements:2,hasMore:requestedPage===0}});
    }
    if(["/api/operations/replay-audits/page","/api/operations/outbox/failures/page","/api/operations/outbox/retry-audits/page","/api/deliveries/page","/api/alerts/page","/api/orders/page"].includes(url.pathname))return route.fulfill({...common,json:{items:[],page:0,size:100,totalElements:0,hasMore:false}});
    if(["/api/routes","/api/telemetry/points","/api/reports/daily-kpis"].includes(url.pathname))return route.fulfill({...common,json:[]});
    if(url.pathname==="/api/stream/deliveries")return route.fulfill({status:200,contentType:"text/event-stream",body:"event: connected\ndata: {}\n\n",headers:{"Access-Control-Allow-Origin":"*"}});
    return route.fulfill({status:404,...common,json:{error:"not_found"}});
  });
  return requestedPages;
}

test("loads one next DLQ page for immediate repeated input",async({page})=>{
  const requestedPages=await mockRecoveryPages(page);
  await page.goto("/console#recovery");
  const loadMore=page.locator(".loadMoreDlq");
  await expect(loadMore).toBeVisible();
  requestedPages.length=0;
  await loadMore.evaluate(button=>{const target=button as HTMLButtonElement;target.click();target.click()});
  await expect(loadMore).toBeDisabled();
  await expect(loadMore).toBeHidden({timeout:1_500});
  expect(requestedPages).toEqual([1]);
  await expect(page.getByText("trace-page-2")).toBeVisible();
});

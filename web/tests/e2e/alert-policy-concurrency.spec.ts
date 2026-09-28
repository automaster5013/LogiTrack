import { expect, test, type Page } from "@playwright/test";
import type { AlertPolicy, AlertPolicyAudit, Delivery } from "../../app/types";

const now="2026-09-28T04:00:00Z";
const policies:AlertPolicy[]=[
  {id:"policy-global",vehicleId:"*",deviationOpenMeters:500,deviationCloseMeters:300,criticalDeviationMeters:1500,delayOpenSeconds:600,delayCloseSeconds:300,criticalDelaySeconds:1800,updatedAt:now,updatedBy:"admin"},
  {id:"policy-truck",vehicleId:"TRUCK-01",deviationOpenMeters:400,deviationCloseMeters:200,criticalDeviationMeters:1200,delayOpenSeconds:480,delayCloseSeconds:240,criticalDelaySeconds:1500,updatedAt:now,updatedBy:"admin"},
];
const audit:AlertPolicyAudit={...policies[1],id:"audit-policy-1",policyId:"policy-truck",action:"UPSERT",actor:"admin",occurredAt:now};
const delivery:Delivery={id:"delivery-policy-1",orderNumber:"ORD-POLICY-1",vehicleId:"TRUCK-01",status:"IN_TRANSIT",originName:"Seoul Hub",originLat:37.56,originLon:126.97,destinationName:"Incheon DC",destinationLat:37.45,destinationLon:126.70,currentLat:37.5,currentLon:126.8,progress:0.5};

type PolicyFixture={saveFailuresBeforeSuccess?:number;resetFailuresBeforeSuccess?:number;restoreFailuresBeforeSuccess?:number};

async function mockPolicies(page:Page,fixture:PolicyFixture={}){
  const saveRequests:string[]=[];
  const resetRequests:string[]=[];
  const restoreRequests:string[]=[];
  await page.route("**/api/**",async route=>{
    const request=route.request();
    const url=new URL(request.url());
    const common={headers:{"Access-Control-Allow-Origin":"*","Content-Type":"application/json"}};
    if(url.pathname==="/api/alert-policies"&&request.method()==="POST"){
      saveRequests.push(request.postDataJSON().vehicleId);
      await new Promise(resolve=>setTimeout(resolve,1_000));
      if(saveRequests.length<=(fixture.saveFailuresBeforeSuccess||0))return route.fulfill({status:503,...common,json:{error:"temporarily_unavailable"}});
      return route.fulfill({...common,json:policies.find(policy=>policy.vehicleId===saveRequests.at(-1))||policies[0]});
    }
    const restoreMatch=url.pathname.match(/^\/api\/alert-policies\/audits\/([^/]+)\/restore$/);
    if(restoreMatch&&request.method()==="POST"){
      restoreRequests.push(restoreMatch[1]);
      await new Promise(resolve=>setTimeout(resolve,1_000));
      if(restoreRequests.length<=(fixture.restoreFailuresBeforeSuccess||0))return route.fulfill({status:503,...common,json:{error:"temporarily_unavailable"}});
      return route.fulfill({...common,json:policies[1]});
    }
    const resetMatch=url.pathname.match(/^\/api\/alert-policies\/([^/]+)$/);
    if(resetMatch&&request.method()==="DELETE"){
      resetRequests.push(decodeURIComponent(resetMatch[1]));
      await new Promise(resolve=>setTimeout(resolve,1_000));
      if(resetRequests.length<=(fixture.resetFailuresBeforeSuccess||0))return route.fulfill({status:503,...common,json:{error:"temporarily_unavailable"}});
      return route.fulfill({status:204,...common});
    }
    if(url.pathname==="/api/alert-policies")return route.fulfill({...common,json:policies});
    if(url.pathname==="/api/alert-policies/audits/page")return route.fulfill({...common,json:{items:[audit],page:0,size:100,totalElements:1,hasMore:false}});
    if(url.pathname==="/api/deliveries/page")return route.fulfill({...common,json:{items:[delivery],page:0,size:100,totalElements:1,hasMore:false}});
    if(["/api/alerts/page","/api/orders/page"].includes(url.pathname))return route.fulfill({...common,json:{items:[],page:0,size:100,totalElements:0,hasMore:false}});
    if(["/api/routes","/api/telemetry/points","/api/reports/daily-kpis"].includes(url.pathname))return route.fulfill({...common,json:[]});
    if(url.pathname==="/api/stream/deliveries")return route.fulfill({status:200,contentType:"text/event-stream",body:"event: connected\ndata: {}\n\n",headers:{"Access-Control-Allow-Origin":"*"}});
    return route.fulfill({status:404,...common,json:{error:"not_found"}});
  });
  return {saveRequests,resetRequests,restoreRequests};
}

test("sends one policy save request for immediate repeated input",async({page})=>{
  const {saveRequests}=await mockPolicies(page);
  await page.goto("/console#settings");
  const save=page.locator(".policyActions button").first();
  await expect(save).toBeVisible();
  await save.evaluate(button=>{const target=button as HTMLButtonElement;target.click();target.click()});
  await expect(save).toBeDisabled();
  await expect(save).toBeEnabled({timeout:1_500});
  expect(saveRequests).toEqual(["*"]);
});

test("keeps a policy save error visible until retry succeeds",async({page})=>{
  const {saveRequests}=await mockPolicies(page,{saveFailuresBeforeSuccess:1});
  await page.goto("/console#settings");
  const save=page.getByRole("button",{name:"변경 이력과 함께 저장"});
  const error=page.getByText("경고 정책 저장에 실패했습니다. 해제 < 경고 ≤ 긴급 순서를 확인해 주세요.");
  await save.click();
  await expect(error).toBeVisible({timeout:1_500});
  await save.click();
  await expect(error).toBeVisible();
  await expect(save).toBeEnabled({timeout:1_500});
  await expect(error).toBeHidden();
  expect(saveRequests).toEqual(["*","*"]);
});

test("sends one policy reset request for immediate repeated input",async({page})=>{
  const {resetRequests}=await mockPolicies(page);
  page.on("dialog",dialog=>dialog.accept());
  await page.goto("/console#settings");
  await page.getByLabel("적용 범위").selectOption("TRUCK-01");
  const reset=page.getByRole("button",{name:"TRUCK-01 전용 정책을 전체 차량 기본값으로 전환"});
  await reset.evaluate(button=>{const target=button as HTMLButtonElement;target.click();target.click()});
  await expect(reset).toBeDisabled();
  await expect(reset).toBeEnabled({timeout:1_500});
  expect(resetRequests).toEqual(["TRUCK-01"]);
});

test("keeps a policy reset error visible until retry succeeds",async({page})=>{
  const {resetRequests}=await mockPolicies(page,{resetFailuresBeforeSuccess:1});
  page.on("dialog",dialog=>dialog.accept());
  await page.goto("/console#settings");
  await page.getByLabel("적용 범위").selectOption("TRUCK-01");
  const reset=page.getByRole("button",{name:"TRUCK-01 전용 정책을 전체 차량 기본값으로 전환"});
  const error=page.getByText("차량 정책을 전역 기본값으로 되돌리지 못했습니다.");
  await reset.click();
  await expect(error).toBeVisible({timeout:1_500});
  await reset.click();
  await expect(error).toBeVisible();
  await expect(reset).toBeEnabled({timeout:1_500});
  await expect(error).toBeHidden();
  expect(resetRequests).toEqual(["TRUCK-01","TRUCK-01"]);
});

test("sends one policy restore request for immediate repeated input",async({page})=>{
  const {restoreRequests}=await mockPolicies(page);
  page.on("dialog",dialog=>dialog.accept());
  await page.goto("/console#settings");
  const restore=page.getByRole("button",{name:"TRUCK-01 정책 이력 복원"});
  await restore.evaluate(button=>{const target=button as HTMLButtonElement;target.click();target.click()});
  await expect(restore).toBeDisabled();
  await expect(restore).toBeEnabled({timeout:1_500});
  expect(restoreRequests).toEqual([audit.id]);
});

test("keeps a policy restore error visible until retry succeeds",async({page})=>{
  const {restoreRequests}=await mockPolicies(page,{restoreFailuresBeforeSuccess:1});
  page.on("dialog",dialog=>dialog.accept());
  await page.goto("/console#settings");
  const restore=page.getByRole("button",{name:"TRUCK-01 정책 이력 복원"});
  const error=page.getByText("감사 이력에서 경고 정책을 복원하지 못했습니다.");
  await restore.click();
  await expect(error).toBeVisible({timeout:1_500});
  await restore.click();
  await expect(error).toBeVisible();
  await expect(restore).toBeEnabled({timeout:1_500});
  await expect(error).toBeHidden();
  expect(restoreRequests).toEqual([audit.id,audit.id]);
});

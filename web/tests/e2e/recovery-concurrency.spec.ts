import { expect, test, type Page } from "@playwright/test";
import type { DeadLetterEvent, DiscardPlan, OutboxFailure } from "../../app/types";

const failedAt = "2026-09-28T01:00:00Z";
const events: DeadLetterEvent[] = [
  {
    id: "00000000-0000-4000-8000-000000000101",
    originalTopic: "telemetry.events.DLT",
    messageKey: "delivery-101",
    payload: "{}",
    traceId: "trace-recovery-101",
    exceptionMessage: "Telemetry payload could not be processed",
    dlqPartition: 0,
    dlqOffset: 101,
    status: "PENDING",
    failedAt,
  },
  {
    id: "00000000-0000-4000-8000-000000000102",
    originalTopic: "telemetry.events.DLT",
    messageKey: "delivery-102",
    payload: "{}",
    traceId: "trace-recovery-102",
    exceptionMessage: "Telemetry payload could not be processed",
    dlqPartition: 0,
    dlqOffset: 102,
    status: "PENDING",
    failedAt,
  },
];
const outboxFailures: OutboxFailure[] = [
  { id: "failure1-0000-4000-8000-000000000101", aggregateType: "Delivery", aggregateId: "delivery-101", eventType: "DeliveryUpdated", topic: "delivery.events", attempts: 3, lastError: "Broker unavailable", createdAt: failedAt, status: "FAILED" },
  { id: "failure2-0000-4000-8000-000000000102", aggregateType: "Delivery", aggregateId: "delivery-102", eventType: "DeliveryDelayed", topic: "delivery.events", attempts: 4, lastError: "Broker unavailable", createdAt: failedAt, status: "FAILED" },
];

type RecoveryFixture = { replayFailuresBeforeSuccessById?: Record<string,number>; discardFailuresBeforeSuccessById?: Record<string,number>; outboxFailuresBeforeSuccessById?: Record<string,number>; discardPlanFailuresBeforeSuccess?:number; discardPlanExecutionFailuresBeforeSuccess?:number };

async function mockRecovery(page: Page, fixture: RecoveryFixture = {}) {
  const replayRequests: string[] = [];
  const discardRequests: string[] = [];
  const discardPlanRequests: string[][] = [];
  const discardPlanExecutionRequests: string[] = [];
  const outboxRetryRequests: string[] = [];
  const discardPlan: DiscardPlan = { id:"00000000-0000-4000-8000-000000000201", actor:"control-tower", reason:"invalid telemetry payloads", eventIds:[events[0].id], status:"PREPARED", createdAt:failedAt, expiresAt:"2026-09-28T02:00:00Z", succeededCount:0, failedCount:0 };
  await page.route("**/api/**", async route => {
    const request = route.request();
    const url = new URL(request.url());
    const common = { headers: { "Access-Control-Allow-Origin": "*", "Content-Type": "application/json" } };
    const replayMatch = url.pathname.match(/^\/api\/operations\/dlq\/([^/]+)\/replay$/);
    if (replayMatch && request.method() === "POST") {
      replayRequests.push(replayMatch[1]);
      await new Promise(resolve => setTimeout(resolve, replayMatch[1] === events[0].id ? 1_000 : 2_500));
      const requestCount = replayRequests.filter(id => id === replayMatch[1]).length;
      if (requestCount <= (fixture.replayFailuresBeforeSuccessById?.[replayMatch[1]] || 0)) return route.fulfill({ status: 503, ...common, json: { error: "temporarily_unavailable" } });
      return route.fulfill({ status: 204, ...common });
    }
    const discardMatch = url.pathname.match(/^\/api\/operations\/dlq\/([^/]+)\/discard$/);
    if (discardMatch && request.method() === "POST") {
      discardRequests.push(discardMatch[1]);
      await new Promise(resolve => setTimeout(resolve, 1_000));
      const requestCount = discardRequests.filter(id => id === discardMatch[1]).length;
      if (requestCount <= (fixture.discardFailuresBeforeSuccessById?.[discardMatch[1]] || 0)) return route.fulfill({ status: 503, ...common, json: { error: "temporarily_unavailable" } });
      return route.fulfill({ status: 204, ...common });
    }
    if (url.pathname === "/api/operations/discard-plans" && request.method() === "POST") {
      const body = request.postDataJSON() as { eventIds:string[]; reason:string };
      discardPlanRequests.push(body.eventIds);
      await new Promise(resolve => setTimeout(resolve, 1_000));
      if (discardPlanRequests.length <= (fixture.discardPlanFailuresBeforeSuccess || 0)) return route.fulfill({ status:503, ...common, json:{ error:"temporarily_unavailable" } });
      return route.fulfill({ ...common, json:{ ...discardPlan, eventIds:body.eventIds, reason:body.reason } });
    }
    if (url.pathname === `/api/operations/discard-plans/${discardPlan.id}/execute` && request.method() === "POST") {
      discardPlanExecutionRequests.push(discardPlan.id);
      await new Promise(resolve => setTimeout(resolve, 1_000));
      if (discardPlanExecutionRequests.length <= (fixture.discardPlanExecutionFailuresBeforeSuccess || 0)) return route.fulfill({ status:503, ...common, json:{ error:"temporarily_unavailable" } });
      return route.fulfill({ ...common, json:{ ...discardPlan, status:"EXECUTED", succeededCount:discardPlan.eventIds.length, executedAt:"2026-09-28T01:30:00Z" } });
    }
    const outboxRetryMatch = url.pathname.match(/^\/api\/operations\/outbox\/failures\/([^/]+)\/retry$/);
    if (outboxRetryMatch && request.method() === "POST") {
      outboxRetryRequests.push(outboxRetryMatch[1]);
      await new Promise(resolve => setTimeout(resolve, outboxRetryMatch[1] === outboxFailures[0].id ? 1_000 : 2_500));
      const requestCount = outboxRetryRequests.filter(id => id === outboxRetryMatch[1]).length;
      if (requestCount <= (fixture.outboxFailuresBeforeSuccessById?.[outboxRetryMatch[1]] || 0)) return route.fulfill({ status: 503, ...common, json: { error: "temporarily_unavailable" } });
      return route.fulfill({ status: 204, ...common });
    }
    if (url.pathname === "/api/operations/dlq-page") {
      return route.fulfill({ ...common, json: { items: url.searchParams.get("size") === "1" ? events.slice(0, 1) : events, page: 0, size: Number(url.searchParams.get("size")), totalElements: events.length, hasMore: false } });
    }
    if (url.pathname === "/api/operations/outbox/failures/page") {
      return route.fulfill({ ...common, json: { items: outboxFailures, page: 0, size: 100, totalElements: outboxFailures.length, hasMore: false } });
    }
    if (["/api/operations/replay-audits/page", "/api/operations/outbox/retry-audits/page", "/api/deliveries/page", "/api/alerts/page", "/api/orders/page"].includes(url.pathname)) {
      return route.fulfill({ ...common, json: { items: [], page: 0, size: 100, totalElements: 0, hasMore: false } });
    }
    if (["/api/routes", "/api/telemetry/points", "/api/reports/daily-kpis"].includes(url.pathname)) {
      return route.fulfill({ ...common, json: [] });
    }
    if (url.pathname === "/api/stream/deliveries") {
      return route.fulfill({ status: 200, contentType: "text/event-stream", body: "event: connected\ndata: {}\n\n", headers: { "Access-Control-Allow-Origin": "*" } });
    }
    return route.fulfill({ status: 404, ...common, json: { error: "not_found" } });
  });
  return { replayRequests, discardRequests, discardPlanRequests, discardPlanExecutionRequests, outboxRetryRequests };
}

test("keeps each concurrent DLQ replay disabled until its own request finishes", async ({ page }) => {
  const { replayRequests } = await mockRecovery(page);
  page.on("dialog", dialog => dialog.accept());
  await page.goto("/console#recovery");

  const firstReplay = page.getByRole("button", { name: "trace-recovery-101 재처리" });
  const secondReplay = page.getByRole("button", { name: "trace-recovery-102 재처리" });
  await expect(firstReplay).toBeVisible();

  await firstReplay.click();
  await secondReplay.click();
  await expect(firstReplay).toBeDisabled();
  await expect(secondReplay).toBeDisabled();
  await expect(firstReplay).toBeEnabled({ timeout: 1_500 });
  await expect(secondReplay).toBeDisabled();
  await expect(secondReplay).toBeEnabled({ timeout: 3_000 });
  expect(replayRequests).toEqual([events[0].id, events[1].id]);
});

test("keeps each concurrent outbox retry disabled until its own request finishes", async ({ page }) => {
  const { outboxRetryRequests } = await mockRecovery(page);
  page.on("dialog", dialog => dialog.accept());
  await page.goto("/console#recovery");

  const firstRetry = page.getByRole("button", { name: "DeliveryUpdated failure1 재발행" });
  const secondRetry = page.getByRole("button", { name: "DeliveryDelayed failure2 재발행" });
  await expect(firstRetry).toBeVisible();

  await firstRetry.click();
  await secondRetry.click();
  await expect(firstRetry).toBeDisabled();
  await expect(secondRetry).toBeDisabled();
  await expect(firstRetry).toBeEnabled({ timeout: 1_500 });
  await expect(secondRetry).toBeDisabled();
  await expect(secondRetry).toBeEnabled({ timeout: 3_000 });
  expect(outboxRetryRequests).toEqual([outboxFailures[0].id, outboxFailures[1].id]);
});

test("keeps a failed DLQ replay error until that event recovers", async ({ page }) => {
  const { replayRequests } = await mockRecovery(page, { replayFailuresBeforeSuccessById: { [events[0].id]: 1 } });
  page.on("dialog", dialog => dialog.accept());
  await page.goto("/console#recovery");

  const firstReplay = page.getByRole("button", { name: "trace-recovery-101 재처리" });
  const secondReplay = page.getByRole("button", { name: "trace-recovery-102 재처리" });
  await firstReplay.click();
  await secondReplay.click();
  const replayError = page.getByText("DLQ 이벤트 재처리에 실패했습니다.");
  await expect(replayError).toBeVisible({ timeout: 1_500 });
  await expect(secondReplay).toBeEnabled({ timeout: 3_000 });
  await expect(replayError).toBeVisible();

  await firstReplay.click();
  await expect(replayError).toBeVisible();
  await expect(firstReplay).toBeEnabled({ timeout: 1_500 });
  await expect(replayError).toBeHidden();
  expect(replayRequests).toEqual([events[0].id,events[1].id,events[0].id]);
});

test("keeps a failed outbox retry error until that event recovers", async ({ page }) => {
  const { outboxRetryRequests } = await mockRecovery(page, { outboxFailuresBeforeSuccessById: { [outboxFailures[0].id]: 1 } });
  page.on("dialog", dialog => dialog.accept());
  await page.goto("/console#recovery");

  const firstRetry = page.getByRole("button", { name: "DeliveryUpdated failure1 재발행" });
  const secondRetry = page.getByRole("button", { name: "DeliveryDelayed failure2 재발행" });
  await firstRetry.click();
  await secondRetry.click();
  const retryError = page.getByText("Outbox 이벤트 재발행에 실패했습니다.");
  await expect(retryError).toBeVisible({ timeout: 1_500 });
  await expect(secondRetry).toBeEnabled({ timeout: 3_000 });
  await expect(retryError).toBeVisible();

  await firstRetry.click();
  await expect(retryError).toBeVisible();
  await expect(firstRetry).toBeEnabled({ timeout: 1_500 });
  await expect(retryError).toBeHidden();
  expect(outboxRetryRequests).toEqual([outboxFailures[0].id,outboxFailures[1].id,outboxFailures[0].id]);
});

test("sends one DLQ replay request for immediate repeated input", async ({ page }) => {
  const { replayRequests } = await mockRecovery(page);
  page.on("dialog", dialog => dialog.accept());
  await page.goto("/console#recovery");

  const replay = page.getByRole("button", { name: "trace-recovery-101 재처리" });
  await expect(replay).toBeVisible();
  await replay.evaluate(button => {
    const replayButton = button as HTMLButtonElement;
    replayButton.click();
    replayButton.click();
  });

  await expect(replay).toBeDisabled();
  await expect(replay).toBeEnabled({ timeout: 1_500 });
  expect(replayRequests).toEqual([events[0].id]);
});

test("sends one outbox retry request for immediate repeated input", async ({ page }) => {
  const { outboxRetryRequests } = await mockRecovery(page);
  page.on("dialog", dialog => dialog.accept());
  await page.goto("/console#recovery");

  const retry = page.getByRole("button", { name: "DeliveryUpdated failure1 재발행" });
  await expect(retry).toBeVisible();
  await retry.evaluate(button => {
    const retryButton = button as HTMLButtonElement;
    retryButton.click();
    retryButton.click();
  });

  await expect(retry).toBeDisabled();
  await expect(retry).toBeEnabled({ timeout: 1_500 });
  expect(outboxRetryRequests).toEqual([outboxFailures[0].id]);
});

test("sends one DLQ discard request for immediate repeated input", async ({ page }) => {
  const { discardRequests } = await mockRecovery(page);
  page.on("dialog", dialog => dialog.type()==="prompt"?dialog.accept("invalid telemetry payload"):dialog.accept());
  await page.goto("/console#recovery");

  const discard = page.getByRole("button", { name: "trace-recovery-101 영구 폐기" });
  await expect(discard).toBeVisible();
  await discard.evaluate(button => {
    const discardButton = button as HTMLButtonElement;
    discardButton.click();
    discardButton.click();
  });

  await expect(discard).toBeDisabled();
  await expect(discard).toBeEnabled({ timeout: 1_500 });
  expect(discardRequests).toEqual([events[0].id]);
});

test("keeps a DLQ discard error visible until retry succeeds", async ({ page }) => {
  const { discardRequests } = await mockRecovery(page, { discardFailuresBeforeSuccessById: { [events[0].id]: 1 } });
  page.on("dialog", dialog => dialog.type()==="prompt"?dialog.accept("invalid telemetry payload"):dialog.accept());
  await page.goto("/console#recovery");

  const discard = page.getByRole("button", { name: "trace-recovery-101 영구 폐기" });
  const discardError = page.getByText("DLQ 이벤트 폐기에 실패했습니다. 폐기 사유를 확인해 주세요.");
  await discard.click();
  await expect(discardError).toBeVisible({ timeout: 1_500 });

  await discard.click();
  await expect(discardError).toBeVisible();
  await expect(discard).toBeEnabled({ timeout: 1_500 });
  await expect(discardError).toBeHidden();
  expect(discardRequests).toEqual([events[0].id,events[0].id]);
});

test("sends one bulk discard plan request for immediate repeated input", async ({ page }) => {
  const { discardPlanRequests } = await mockRecovery(page);
  await page.goto("/console#recovery");
  await page.getByRole("checkbox", { name:"trace-recovery-101 일괄 폐기 선택" }).check();
  await page.getByPlaceholder("폐기 사유를 입력하세요").fill("invalid telemetry payloads");
  const prepare = page.getByRole("button", { name:"선택한 1건 검토" });
  await prepare.evaluate(button => {
    const prepareButton = button as HTMLButtonElement;
    prepareButton.click();
    prepareButton.click();
  });

  await expect(page.getByRole("button", { name:"검토 준비 중…" })).toBeDisabled();
  await expect(page.getByText("승인 대기 · 1건")).toBeVisible({ timeout:1_500 });
  expect(discardPlanRequests).toEqual([[events[0].id]]);
});

test("keeps a bulk discard plan error visible until retry succeeds", async ({ page }) => {
  const { discardPlanRequests } = await mockRecovery(page, { discardPlanFailuresBeforeSuccess:1 });
  await page.goto("/console#recovery");
  await page.getByRole("checkbox", { name:"trace-recovery-101 일괄 폐기 선택" }).check();
  await page.getByPlaceholder("폐기 사유를 입력하세요").fill("invalid telemetry payloads");
  const prepare = page.getByRole("button", { name:"선택한 1건 검토" });
  const error = page.getByText("일괄 폐기 계획 생성에 실패했습니다. 선택 항목과 사유를 확인해 주세요.");
  await prepare.click();
  await expect(error).toBeVisible({ timeout:1_500 });

  await prepare.click();
  await expect(error).toBeVisible();
  await expect(page.getByText("승인 대기 · 1건")).toBeVisible({ timeout:1_500 });
  await expect(error).toBeHidden();
  expect(discardPlanRequests).toEqual([[events[0].id],[events[0].id]]);
});

test("sends one bulk discard execution request for immediate repeated input", async ({ page }) => {
  const { discardPlanExecutionRequests } = await mockRecovery(page);
  await page.goto("/console#recovery");
  await page.getByRole("checkbox", { name:"trace-recovery-101 일괄 폐기 선택" }).check();
  await page.getByPlaceholder("폐기 사유를 입력하세요").fill("invalid telemetry payloads");
  await page.getByRole("button", { name:"선택한 1건 검토" }).click();
  await page.getByLabel("승인어 DISCARD 입력").fill("DISCARD");
  const execute = page.getByRole("button", { name:"영구 폐기 실행" });
  await execute.evaluate(button => {
    const executeButton = button as HTMLButtonElement;
    executeButton.click();
    executeButton.click();
  });

  await expect(page.getByRole("button", { name:"폐기 중…" })).toBeDisabled();
  await expect(page.getByText("실행 완료 · 1건")).toBeVisible({ timeout:1_500 });
  expect(discardPlanExecutionRequests).toEqual(["00000000-0000-4000-8000-000000000201"]);
});

test("keeps a bulk discard execution error visible until retry succeeds", async ({ page }) => {
  const { discardPlanExecutionRequests } = await mockRecovery(page, { discardPlanExecutionFailuresBeforeSuccess:1 });
  await page.goto("/console#recovery");
  await page.getByRole("checkbox", { name:"trace-recovery-101 일괄 폐기 선택" }).check();
  await page.getByPlaceholder("폐기 사유를 입력하세요").fill("invalid telemetry payloads");
  await page.getByRole("button", { name:"선택한 1건 검토" }).click();
  await page.getByLabel("승인어 DISCARD 입력").fill("DISCARD");
  const execute = page.getByRole("button", { name:"영구 폐기 실행" });
  const error = page.getByText("일괄 폐기 실행에 실패했습니다. 계획 만료 또는 이벤트 상태를 확인해 주세요.");
  await execute.click();
  await expect(error).toBeVisible({ timeout:1_500 });

  await execute.click();
  await expect(error).toBeVisible();
  await expect(page.getByText("실행 완료 · 1건")).toBeVisible({ timeout:1_500 });
  await expect(error).toBeHidden();
  expect(discardPlanExecutionRequests).toEqual(["00000000-0000-4000-8000-000000000201","00000000-0000-4000-8000-000000000201"]);
});

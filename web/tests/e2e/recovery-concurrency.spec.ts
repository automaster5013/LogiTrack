import { expect, test, type Page } from "@playwright/test";
import type { DeadLetterEvent, OutboxFailure } from "../../app/types";

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

type RecoveryFixture = { replayFailuresBeforeSuccessById?: Record<string,number>; outboxFailuresBeforeSuccessById?: Record<string,number> };

async function mockRecovery(page: Page, fixture: RecoveryFixture = {}) {
  const replayRequests: string[] = [];
  const outboxRetryRequests: string[] = [];
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
  return { replayRequests, outboxRetryRequests };
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

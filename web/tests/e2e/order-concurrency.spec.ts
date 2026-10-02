import { expect, test, type Page } from "@playwright/test";
import type { CustomerOrder } from "../../app/types";

const timestamp = "2026-09-28T02:00:00Z";
const orders: CustomerOrder[] = [
  { id: "00000000-0000-4000-8000-000000000201", orderNumber: "ORD-E2E-201", status: "READY", originName: "Seoul Hub", originLat: 37.5665, originLon: 126.978, destinationName: "Incheon DC", destinationLat: 37.4563, destinationLon: 126.7052, createdAt: timestamp, updatedAt: timestamp },
  { id: "00000000-0000-4000-8000-000000000202", orderNumber: "ORD-E2E-202", status: "READY", originName: "Seoul Hub", originLat: 37.5665, originLon: 126.978, destinationName: "Busan DC", destinationLat: 35.1796, destinationLon: 129.0756, createdAt: timestamp, updatedAt: timestamp },
];

type OrderFixture = { dispatchFailuresBeforeSuccessById?: Record<string, number>; createFailuresBeforeSuccess?: number };

async function mockOrders(page: Page, fixture: OrderFixture = {}) {
  const dispatchRequests: string[] = [];
  let createRequests = 0;
  await page.route("**/api/**", async route => {
    const request = route.request();
    const url = new URL(request.url());
    const common = { headers: { "Access-Control-Allow-Origin": "*", "Content-Type": "application/json" } };
    const dispatchMatch = url.pathname.match(/^\/api\/orders\/([^/]+)\/dispatch$/);
    if (dispatchMatch && request.method() === "POST") {
      const order = orders.find(candidate => candidate.id === dispatchMatch[1]);
      if (!order) return route.fulfill({ status: 404, ...common, json: { error: "not_found" } });
      dispatchRequests.push(order.id);
      await new Promise(resolve => setTimeout(resolve, order.id === orders[0].id ? 1_000 : 2_500));
      const requestCount = dispatchRequests.filter(id => id === order.id).length;
      if (requestCount <= (fixture.dispatchFailuresBeforeSuccessById?.[order.id] || 0)) {
        return route.fulfill({ status: 503, ...common, json: { error: "temporarily_unavailable" } });
      }
      return route.fulfill({ ...common, json: { ...order, status: "DISPATCHED", deliveryId: `delivery-${order.id.slice(-3)}`, vehicleId: "TRUCK-01", deliveryStatus: "CREATED", updatedAt: timestamp } });
    }
    if (url.pathname === "/api/orders" && request.method() === "POST") {
      createRequests += 1;
      await new Promise(resolve => setTimeout(resolve, 1_000));
      if (createRequests <= (fixture.createFailuresBeforeSuccess || 0)) {
        return route.fulfill({ status: 503, ...common, json: { error: "temporarily_unavailable" } });
      }
      return route.fulfill({ status: 201, ...common, json: { ...orders[0], id: "00000000-0000-4000-8000-000000000203", orderNumber: "ORD-E2E-203" } });
    }
    if (url.pathname === "/api/orders/page") {
      return route.fulfill({ ...common, json: { items: orders, page: 0, size: 100, totalElements: orders.length, hasMore: false } });
    }
    if (["/api/deliveries/page", "/api/alerts/page"].includes(url.pathname)) {
      return route.fulfill({ ...common, json: { items: [], page: 0, size: 100, totalElements: 0, hasMore: false } });
    }
    if (["/api/routes", "/api/telemetry/points"].includes(url.pathname)) {
      return route.fulfill({ ...common, json: [] });
    }
    if (url.pathname === "/api/operations/dlq-page") {
      return route.fulfill({ ...common, json: { items: [], page: 0, size: 1, totalElements: 0, hasMore: false } });
    }
    if (url.pathname === "/api/stream/deliveries") {
      return route.fulfill({ status: 200, contentType: "text/event-stream", body: "event: connected\ndata: {}\n\n", headers: { "Access-Control-Allow-Origin": "*" } });
    }
    return route.fulfill({ status: 404, ...common, json: { error: "not_found" } });
  });
  return { dispatchRequests, createRequests: () => createRequests };
}

test("tracks concurrent order dispatches independently", async ({ page }) => {
  const { dispatchRequests } = await mockOrders(page);
  await page.goto("/console#orders");

  const firstDispatch = page.getByRole("button", { name: "ORD-E2E-201 차량 배차" });
  const secondDispatch = page.getByRole("button", { name: "ORD-E2E-202 차량 배차" });
  await expect(firstDispatch).toBeVisible();

  await firstDispatch.click();
  await secondDispatch.click();
  await expect(firstDispatch).toBeDisabled();
  await expect(secondDispatch).toBeDisabled();
  await expect(firstDispatch).toBeEnabled({ timeout: 1_500 });
  await expect(secondDispatch).toBeDisabled();
  await expect(secondDispatch).toBeEnabled({ timeout: 3_000 });
  expect(dispatchRequests).toEqual([orders[0].id, orders[1].id]);
});

test("sends one dispatch request for immediate repeated input", async ({ page }) => {
  const { dispatchRequests } = await mockOrders(page);
  await page.goto("/console#orders");

  const dispatch = page.getByRole("button", { name: "ORD-E2E-201 차량 배차" });
  await expect(dispatch).toBeVisible();
  await dispatch.evaluate(button => {
    const dispatchButton = button as HTMLButtonElement;
    dispatchButton.click();
    dispatchButton.click();
  });

  await expect(dispatch).toBeDisabled();
  await expect(dispatch).toBeEnabled({ timeout: 1_500 });
  expect(dispatchRequests).toEqual([orders[0].id]);
});

test("pauses order dispatch while offline and restores it online", async ({ page, context }) => {
  const { dispatchRequests } = await mockOrders(page);
  await page.goto("/console#orders");
  const dispatch = page.getByRole("button", { name: "ORD-E2E-201 차량 배차" });
  await expect(dispatch).toBeVisible();

  await context.setOffline(true);
  await expect(dispatch).toHaveText("네트워크 연결 대기 중…");
  await expect(dispatch).toBeDisabled();
  expect(dispatchRequests).toHaveLength(0);

  await context.setOffline(false);
  await expect(dispatch).toHaveText("차량 배차");
  await expect(dispatch).toBeEnabled();
  await dispatch.click();
  await expect(dispatch).toBeEnabled({ timeout: 1_500 });
  expect(dispatchRequests).toEqual([orders[0].id]);
});

test("keeps a failed dispatch error until that order recovers", async ({ page }) => {
  const { dispatchRequests } = await mockOrders(page, { dispatchFailuresBeforeSuccessById: { [orders[0].id]: 1 } });
  await page.goto("/console#orders");

  const firstDispatch = page.getByRole("button", { name: "ORD-E2E-201 차량 배차" });
  const secondDispatch = page.getByRole("button", { name: "ORD-E2E-202 차량 배차" });
  await expect(firstDispatch).toBeVisible();
  await firstDispatch.click();
  await secondDispatch.click();

  const dispatchError = page.getByText("주문 배차에 실패했습니다.");
  await expect(dispatchError).toBeVisible({ timeout: 1_500 });
  await expect(secondDispatch).toBeEnabled({ timeout: 3_000 });
  await expect(dispatchError).toBeVisible();

  await firstDispatch.click();
  await expect(dispatchError).toBeVisible();
  await expect(firstDispatch).toBeEnabled({ timeout: 1_500 });
  await expect(dispatchError).toBeHidden();
  expect(dispatchRequests).toEqual([orders[0].id, orders[1].id, orders[0].id]);
});

test("sends one create request for immediate repeated input", async ({ page }) => {
  const fixture = await mockOrders(page);
  await page.goto("/console#orders");

  const createButton = page.locator(".workspacePrimaryActions > .primary");
  await expect(createButton).toHaveText("+ 새 주문");
  await createButton.evaluate(button => {
    const orderButton = button as HTMLButtonElement;
    orderButton.click();
    orderButton.click();
  });

  await expect(createButton).toBeDisabled();
  await expect(createButton).toBeEnabled({ timeout: 1_500 });
  expect(fixture.createRequests()).toBe(1);
});

test("pauses order creation while offline and restores it online", async ({ page, context }) => {
  const fixture = await mockOrders(page);
  await page.goto("/console#orders");

  const createButton = page.locator(".workspacePrimaryActions > .primary");
  await context.setOffline(true);
  await expect(createButton).toHaveText("네트워크 연결 대기 중…");
  await expect(createButton).toBeDisabled();
  expect(fixture.createRequests()).toBe(0);

  await context.setOffline(false);
  await expect(createButton).toHaveText("+ 새 주문");
  await expect(createButton).toBeEnabled();
  await createButton.click();
  await expect(createButton).toBeEnabled({ timeout: 1_500 });
  expect(fixture.createRequests()).toBe(1);
});

test("keeps an order creation error visible until retry succeeds", async ({ page }) => {
  const fixture = await mockOrders(page, { createFailuresBeforeSuccess: 1 });
  await page.goto("/console#orders");

  const createButton = page.locator(".workspacePrimaryActions > .primary");
  const createError = page.getByText("주문 생성에 실패했습니다.");
  await createButton.click();
  await expect(createError).toBeVisible({ timeout: 1_500 });

  await createButton.click();
  await expect(createError).toBeVisible();
  await expect(createButton).toBeEnabled({ timeout: 1_500 });
  await expect(createError).toBeHidden();
  expect(fixture.createRequests()).toBe(2);
});

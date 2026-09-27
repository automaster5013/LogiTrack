import { expect, test, type Page } from "@playwright/test";
import type { CustomerOrder } from "../../app/types";

const timestamp = "2026-09-28T02:00:00Z";
const orders: CustomerOrder[] = [
  { id: "00000000-0000-4000-8000-000000000201", orderNumber: "ORD-E2E-201", status: "READY", originName: "Seoul Hub", originLat: 37.5665, originLon: 126.978, destinationName: "Incheon DC", destinationLat: 37.4563, destinationLon: 126.7052, createdAt: timestamp, updatedAt: timestamp },
  { id: "00000000-0000-4000-8000-000000000202", orderNumber: "ORD-E2E-202", status: "READY", originName: "Seoul Hub", originLat: 37.5665, originLon: 126.978, destinationName: "Busan DC", destinationLat: 35.1796, destinationLon: 129.0756, createdAt: timestamp, updatedAt: timestamp },
];

async function mockOrders(page: Page) {
  const dispatchRequests: string[] = [];
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
      return route.fulfill({ ...common, json: { ...order, status: "DISPATCHED", deliveryId: `delivery-${order.id.slice(-3)}`, vehicleId: "TRUCK-01", deliveryStatus: "CREATED", updatedAt: timestamp } });
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
  return dispatchRequests;
}

test("tracks concurrent order dispatches independently", async ({ page }) => {
  const dispatchRequests = await mockOrders(page);
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
  const dispatchRequests = await mockOrders(page);
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

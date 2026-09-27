import { expect, test } from "@playwright/test";

const now = "2026-09-27T08:00:00Z";
const deliveries = Array.from({ length: 6 }, (_, index) => {
  const originLon = 126.82 + index * 0.025;
  const originLat = 37.42 + index * 0.018;
  const destinationLon = 127.02 + index * 0.025;
  const destinationLat = 37.54 + index * 0.018;
  return {
    id: `00000000-0000-4000-8000-00000000000${index + 1}`,
    orderNumber: `ORD-DEMO-${index + 1}`,
    vehicleId: `TRUCK-0${index + 1}`,
    status: "DELIVERED",
    originName: `출발지 ${index + 1}`,
    originLat,
    originLon,
    destinationName: `도착지 ${index + 1}`,
    destinationLat,
    destinationLon,
    currentLat: destinationLat,
    currentLon: destinationLon,
    progress: 1,
    eta: now,
    lastTelemetryAt: now,
  };
});

const routes = deliveries.map((delivery, index) => ({
  id: `10000000-0000-4000-8000-00000000000${index + 1}`,
  deliveryId: delivery.id,
  provider: "test",
  algorithmVersion: "e2e",
  geometry: { type: "LineString", coordinates: [[delivery.originLon, delivery.originLat], [delivery.currentLon, delivery.currentLat]] },
  geometryHash: `test-${index + 1}`,
  distanceMeters: 26_000 + index * 1_000,
  durationSeconds: 3_600,
  plannedEta: now,
  generatedAt: now,
}));

test("shows completed vehicles automatically when no delivery is active", async ({ page }) => {
  await page.route("**/api/**", async route => {
    const url = new URL(route.request().url());
    const common = { headers: { "Access-Control-Allow-Origin": "*", "Content-Type": "application/json" } };
    if (url.pathname === "/api/deliveries/page") return route.fulfill({ ...common, json: { items: deliveries, page: 0, size: 100, totalElements: 6, hasMore: false } });
    if (url.pathname === "/api/alerts/page") return route.fulfill({ ...common, json: { items: [], page: 0, size: 100, totalElements: 0, hasMore: false } });
    if (url.pathname === "/api/routes") return route.fulfill({ ...common, json: routes });
    if (url.pathname === "/api/telemetry/points" || url.pathname === "/api/reports/daily-kpis") return route.fulfill({ ...common, json: [] });
    if (url.pathname === "/api/operations/dlq-page") return route.fulfill({ ...common, json: { items: [], page: 0, size: 1, totalElements: 0, hasMore: false } });
    if (url.pathname === "/api/stream/deliveries") return route.fulfill({ status: 200, contentType: "text/event-stream", body: "event: connected\ndata: {}\n\n", headers: { "Access-Control-Allow-Origin": "*" } });
    return route.fulfill({ status: 404, ...common, json: { error: "not_found" } });
  });

  await page.goto("/console#overview");

  await expect(page.getByText("전체 6건")).toBeVisible();
  await expect(page.getByRole("button", { name: "전체 6", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByRole("button", { name: "진행 중 0", exact: true })).toHaveAttribute("aria-pressed", "false");
  await expect(page.getByLabel("선택한 차량")).toHaveValue(deliveries[0].id);
  await expect(page.getByLabel("선택한 차량").locator("option")).toHaveCount(6);
  await expect(page.locator(".focusStats")).toContainText("26.0 km");
  await expect(page.locator(".focusStats")).toContainText("TRUCK-01");
});

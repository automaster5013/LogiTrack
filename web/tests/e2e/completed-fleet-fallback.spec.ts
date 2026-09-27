import { expect, test, type Page } from "@playwright/test";

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

async function mockOverview(page: Page, deliveryRows: typeof deliveries) {
  const routes = deliveryRows.map((delivery, index) => ({
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

  await page.route("**/api/**", async route => {
    const url = new URL(route.request().url());
    const common = { headers: { "Access-Control-Allow-Origin": "*", "Content-Type": "application/json" } };
    if (url.pathname === "/api/deliveries/page") return route.fulfill({ ...common, json: { items: deliveryRows, page: 0, size: 100, totalElements: deliveryRows.length, hasMore: false } });
    if (url.pathname === "/api/orders/page") return route.fulfill({ ...common, json: { items: [], page: 0, size: 100, totalElements: 0, hasMore: false } });
    if (url.pathname === "/api/alerts/page") return route.fulfill({ ...common, json: { items: [], page: 0, size: 100, totalElements: 0, hasMore: false } });
    if (url.pathname === "/api/routes") return route.fulfill({ ...common, json: routes });
    if (url.pathname === "/api/telemetry/points" || url.pathname === "/api/reports/daily-kpis") return route.fulfill({ ...common, json: [] });
    if (url.pathname === "/api/operations/dlq-page") return route.fulfill({ ...common, json: { items: [], page: 0, size: 1, totalElements: 0, hasMore: false } });
    if (url.pathname === "/api/stream/deliveries") return route.fulfill({ status: 200, contentType: "text/event-stream", body: "event: connected\ndata: {}\n\n", headers: { "Access-Control-Allow-Origin": "*" } });
    return route.fulfill({ status: 404, ...common, json: { error: "not_found" } });
  });
}

test("shows completed vehicles automatically when no delivery is active", async ({ page }) => {
  await mockOverview(page, deliveries);

  await page.goto("/console#overview");

  await expect(page.getByText("전체 6건")).toBeVisible();
  await expect(page.getByRole("button", { name: "전체 6", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByRole("button", { name: "진행 중 0", exact: true })).toHaveAttribute("aria-pressed", "false");
  await expect(page.getByLabel("선택한 차량")).toHaveValue(deliveries[0].id);
  await expect(page.getByLabel("선택한 차량").locator("option")).toHaveCount(6);
  await expect(page.locator(".focusStats")).toContainText("26.0 km");
  await expect(page.locator(".focusStats")).toContainText("TRUCK-01");
});

test("keeps the map and fleet list in sync when switching scopes", async ({ page }) => {
  await mockOverview(page, deliveries);
  await page.goto("/console#overview");

  const liveScopeButtons = page.getByRole("button", { name: "진행 중 0", exact: true });
  const allScopeButtons = page.getByRole("button", { name: "전체 6", exact: true });
  await expect(allScopeButtons).toHaveAttribute("aria-pressed", "true");

  await liveScopeButtons.first().click();

  await expect(liveScopeButtons).toHaveAttribute("aria-pressed", "true");
  await expect(allScopeButtons).toHaveAttribute("aria-pressed", "false");
  await expect(page.getByText("표시할 차량이 없습니다")).toBeVisible();
  await expect(page.getByLabel("선택한 차량")).toHaveCount(0);

  await page.getByRole("link", { name: "주문·차량" }).click();
  await expect(page.getByRole("heading", { name: "차량 운행 현황" })).toBeVisible();
  await expect(page.getByText("현재 범위와 검색 조건에 맞는 배송이 없습니다.")).toBeVisible();
  await expect(page.getByRole("button", { name: "진행 중 0", exact: true })).toHaveAttribute("aria-pressed", "true");

  await page.getByRole("button", { name: "전체 6", exact: true }).click();

  await expect(page.getByRole("button", { name: "전체 6", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByRole("button", { name: "진행 중 0", exact: true })).toHaveAttribute("aria-pressed", "false");
  await expect(page.getByText("6 / 6건 표시 · 전체 6건")).toBeVisible();
  await expect(page.getByRole("button", { name: /TRUCK-01/ })).toBeVisible();

  await page.getByRole("link", { name: "상황판" }).click();
  await expect(page.getByLabel("선택한 차량")).toHaveValue(deliveries[0].id);
  await expect(page.getByLabel("선택한 차량").locator("option")).toHaveCount(6);
  await expect(page.locator(".focusStats")).toContainText("TRUCK-01");
});

test("keeps fleet search synchronized across the map and vehicle list", async ({ page }) => {
  await mockOverview(page, deliveries);
  await page.goto("/console#overview");

  await page.getByRole("searchbox", { name: "검색", exact: true }).fill("TRUCK-03");

  await expect(page.getByText("1건", { exact: true })).toBeVisible();
  await expect(page.getByLabel("선택한 차량")).toHaveValue(deliveries[2].id);
  await expect(page.getByLabel("선택한 차량").locator("option")).toHaveCount(1);
  await expect(page.locator(".focusStats")).toContainText("TRUCK-03");

  await page.getByRole("link", { name: "주문·차량" }).click();

  await expect(page.getByRole("searchbox", { name: "차량 검색" })).toHaveValue("TRUCK-03");
  await expect(page.getByText("1 / 1건 표시 · 전체 6건")).toBeVisible();
  await expect(page.getByRole("button", { name: /TRUCK-03/ })).toBeVisible();
  await expect(page.getByRole("button", { name: /TRUCK-01/ })).toHaveCount(0);

  await page.getByRole("button", { name: "검색 초기화" }).click();

  await expect(page.getByRole("searchbox", { name: "차량 검색" })).toHaveValue("");
  await expect(page.getByText("6 / 6건 표시 · 전체 6건")).toBeVisible();
  await expect(page.getByRole("button", { name: /TRUCK-01/ })).toBeVisible();

  await page.getByRole("link", { name: "상황판" }).click();
  await expect(page.getByRole("searchbox", { name: "검색", exact: true })).toHaveValue("");
  await expect(page.getByLabel("선택한 차량").locator("option")).toHaveCount(6);
});

test("keeps the live scope when an active delivery exists", async ({ page }) => {
  const activeDeliveries = deliveries.map((delivery, index) => index === 0 ? {
    ...delivery,
    status: "IN_TRANSIT",
    currentLat: (delivery.originLat + delivery.destinationLat) / 2,
    currentLon: (delivery.originLon + delivery.destinationLon) / 2,
    progress: 0.5,
  } : delivery);

  await mockOverview(page, activeDeliveries);
  await page.goto("/console#overview");

  await expect(page.getByText("전체 6건")).toBeVisible();
  await expect(page.getByRole("button", { name: "진행 중 1", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByRole("button", { name: "전체 6", exact: true })).toHaveAttribute("aria-pressed", "false");
  await expect(page.getByLabel("선택한 차량")).toHaveValue(activeDeliveries[0].id);
  await expect(page.getByLabel("선택한 차량").locator("option")).toHaveCount(1);
  await expect(page.locator(".focusStats")).toContainText("26.0 km");
  await expect(page.locator(".focusStats")).toContainText("TRUCK-01");
});

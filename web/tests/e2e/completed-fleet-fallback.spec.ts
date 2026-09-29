import { expect, test, type Page } from "@playwright/test";
import type { DeliveryAlert, TelemetryPoint } from "../../app/types";

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

type StreamFixture = {
  body: string;
  bodiesByConnection?: string[];
  delayMs?: number;
  deliveryRowsAfterFirstLoad?: typeof deliveries;
  alertRowsAfterFirstLoad?: DeliveryAlert[];
  alertRowsByRequest?: DeliveryAlert[][];
  alertPageDelayAfterFirstLoadMs?: number;
  routeDistanceMetersAfterFirstLoad?: number;
  telemetryRows?: TelemetryPoint[];
  telemetryRowsAfterFirstLoad?: TelemetryPoint[];
  acknowledgementResponse?: DeliveryAlert;
  acknowledgementResponses?: Record<string, DeliveryAlert>;
  acknowledgementFailuresBeforeSuccess?: number;
  acknowledgementDelayMs?: number;
  acknowledgementDelayMsById?: Record<string, number>;
  waitForAcknowledgementBeforeStream?: boolean;
  waitForAcknowledgementCountBeforeStream?: number;
  streamDelayAfterAcknowledgementMs?: number;
};

async function mockOverview(page: Page, deliveryRows: typeof deliveries, alertRows: DeliveryAlert[] = [], streamFixture?: StreamFixture) {
  let deliveryRequestCount = 0;
  let alertRequestCount = 0;
  let routeRequestCount = 0;
  let telemetryRequestCount = 0;
  let streamRequestCount = 0;
  let acknowledgementRequestCount = 0;
  let acknowledgementCompletedCount = 0;
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
    if (url.pathname === "/api/runtime-version") return route.fulfill({ ...common, json: { version: "11111111-1111-4111-8111-111111111111", revision: "0123456789abcdef0123456789abcdef01234567", builtAt: "2026-09-28T09:00:00Z", environment: "test" } });
    if (url.pathname.match(/^\/api\/alerts\/[^/]+\/acknowledgement$/) && route.request().method() === "POST") {
      const headers = route.request().headers();
      const traceId = headers["x-trace-id"] || "";
      const alertId = url.pathname.split("/")[3];
      const acknowledgementResponse = streamFixture?.acknowledgementResponses?.[alertId] || streamFixture?.acknowledgementResponse;
      if (headers["x-operator"] !== "control-tower" || !/^[0-9a-f-]{36}$/i.test(traceId) || !acknowledgementResponse) {
        return route.fulfill({ status: 400, ...common, json: { error: "invalid_acknowledgement" } });
      }
      acknowledgementRequestCount += 1;
      const acknowledgementDelayMs = streamFixture.acknowledgementDelayMsById?.[alertId] || streamFixture.acknowledgementDelayMs;
      if (acknowledgementDelayMs) await new Promise(resolve => setTimeout(resolve, acknowledgementDelayMs));
      if (acknowledgementRequestCount <= (streamFixture.acknowledgementFailuresBeforeSuccess || 0)) {
        acknowledgementCompletedCount += 1;
        return route.fulfill({ status: 503, ...common, json: { error: "temporarily_unavailable" } });
      }
      acknowledgementCompletedCount += 1;
      return route.fulfill({ status: 200, ...common, json: acknowledgementResponse });
    }
    if (url.pathname === "/api/deliveries/page") {
      deliveryRequestCount += 1;
      const responseRows = deliveryRequestCount > 1 && streamFixture?.deliveryRowsAfterFirstLoad
        ? streamFixture.deliveryRowsAfterFirstLoad
        : deliveryRows;
      return route.fulfill({ ...common, json: { items: responseRows, page: 0, size: 100, totalElements: responseRows.length, hasMore: false } });
    }
    if (url.pathname === "/api/orders/page") return route.fulfill({ ...common, json: { items: [], page: 0, size: 100, totalElements: 0, hasMore: false } });
    if (url.pathname === "/api/alerts/page") {
      alertRequestCount += 1;
      if (alertRequestCount > 1 && streamFixture?.alertPageDelayAfterFirstLoadMs) await new Promise(resolve => setTimeout(resolve, streamFixture.alertPageDelayAfterFirstLoadMs));
      const responseRows = streamFixture?.alertRowsByRequest?.[Math.min(alertRequestCount - 1, streamFixture.alertRowsByRequest.length - 1)]
        || (alertRequestCount > 1 && streamFixture?.alertRowsAfterFirstLoad ? streamFixture.alertRowsAfterFirstLoad : alertRows);
      return route.fulfill({ ...common, json: { items: responseRows, page: 0, size: 100, totalElements: responseRows.length, hasMore: false } });
    }
    if (url.pathname === "/api/routes") {
      routeRequestCount += 1;
      const requestedIds = new Set((url.searchParams.get("deliveryIds") || "").split(",").filter(Boolean));
      const responseRows = routes.map((item, index) => routeRequestCount > 1 && index === 0 && streamFixture?.routeDistanceMetersAfterFirstLoad
        ? { ...item, distanceMeters: streamFixture.routeDistanceMetersAfterFirstLoad }
        : item);
      return route.fulfill({ ...common, json: requestedIds.size ? responseRows.filter(item => requestedIds.has(item.deliveryId)) : responseRows });
    }
    if (url.pathname === "/api/telemetry/points") {
      telemetryRequestCount += 1;
      const responseRows = telemetryRequestCount > 1 && streamFixture?.telemetryRowsAfterFirstLoad
        ? streamFixture.telemetryRowsAfterFirstLoad
        : streamFixture?.telemetryRows || [];
      const requestedIds = new Set((url.searchParams.get("deliveryIds") || "").split(",").filter(Boolean));
      return route.fulfill({ ...common, json: requestedIds.size ? responseRows.filter(item => requestedIds.has(item.deliveryId)) : responseRows });
    }
    if (url.pathname === "/api/reports/daily-kpis") return route.fulfill({ ...common, json: [] });
    if (url.pathname === "/api/operations/dlq-page") return route.fulfill({ ...common, json: { items: [], page: 0, size: 1, totalElements: 0, hasMore: false } });
    if (url.pathname === "/api/stream/deliveries") {
      streamRequestCount += 1;
      const acknowledgementCountBeforeStream = streamFixture?.waitForAcknowledgementCountBeforeStream || (streamFixture?.waitForAcknowledgementBeforeStream ? 1 : 0);
      if (acknowledgementCountBeforeStream) {
        while (acknowledgementRequestCount < acknowledgementCountBeforeStream) await new Promise(resolve => setTimeout(resolve, 10));
        const streamDelayAfterAcknowledgementMs = streamFixture?.streamDelayAfterAcknowledgementMs;
        if (streamDelayAfterAcknowledgementMs) await new Promise(resolve => setTimeout(resolve, streamDelayAfterAcknowledgementMs));
      }
      if (streamFixture?.delayMs) await new Promise(resolve => setTimeout(resolve, streamFixture.delayMs));
      const bodies = streamFixture?.bodiesByConnection;
      const body = bodies?.[Math.min(streamRequestCount - 1, bodies.length - 1)] || streamFixture?.body || "event: connected\ndata: {}\n\n";
      return route.fulfill({ status: 200, contentType: "text/event-stream", body, headers: { "Access-Control-Allow-Origin": "*" } });
    }
    return route.fulfill({ status: 404, ...common, json: { error: "not_found" } });
  });
  return {
    acknowledgementRequestCount: () => acknowledgementRequestCount,
    acknowledgementCompletedCount: () => acknowledgementCompletedCount,
    alertRequestCount: () => alertRequestCount,
  };
}

function createDenseDeliveries() {
  return Array.from({ length: 51 }, (_, index) => {
    const template = deliveries[index % deliveries.length];
    const sequence = (index + 1).toString().padStart(2, "0");
    return {
      ...template,
      id: `dense-delivery-${sequence}`,
      orderNumber: `ORD-DENSE-${sequence}`,
      vehicleId: `TRUCK-${sequence}`,
      originLat: template.originLat + index * 0.001,
      originLon: template.originLon + index * 0.001,
      destinationLat: template.destinationLat + index * 0.001,
      destinationLon: template.destinationLon + index * 0.001,
      currentLat: template.destinationLat + index * 0.001,
      currentLon: template.destinationLon + index * 0.001,
    };
  });
}

test("keeps the dense fleet map inside the narrow desktop viewport", async ({ page }) => {
  await page.setViewportSize({ width: 900, height: 768 });
  await mockOverview(page, createDenseDeliveries());
  await page.goto("/console#overview");

  await expect(page.getByText("최근 50건을 지도에 표시합니다 · 검색하면 결과를 우선 표시합니다")).toBeVisible();
  const mapBoardBox = await page.locator(".mapBoard").boundingBox();
  const mapShellBox = await page.locator(".mapShell").boundingBox();
  expect(mapBoardBox).not.toBeNull();
  expect(mapShellBox).not.toBeNull();
  expect(mapBoardBox!.y + mapBoardBox!.height).toBeLessThanOrEqual(768);
  expect(mapShellBox!.height).toBeGreaterThanOrEqual(280);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(900);
});

test("shows completed vehicles automatically when no delivery is active", async ({ page }) => {
  await page.setViewportSize({ width: 1024, height: 768 });
  await mockOverview(page, deliveries);

  await page.goto("/console#overview");

  const tabletMapBoardBox = await page.locator(".mapBoard").boundingBox();
  const tabletMapShellBox = await page.locator(".mapShell").boundingBox();
  expect(tabletMapBoardBox).not.toBeNull();
  expect(tabletMapShellBox).not.toBeNull();
  expect(tabletMapBoardBox!.y + tabletMapBoardBox!.height).toBeLessThanOrEqual(768);
  expect(tabletMapShellBox!.height).toBeGreaterThanOrEqual(280);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(1024);

  await page.setViewportSize({ width: 1280, height: 720 });
  const compactMapBoardBox = await page.locator(".mapBoard").boundingBox();
  const compactMapShellBox = await page.locator(".mapShell").boundingBox();
  expect(compactMapBoardBox).not.toBeNull();
  expect(compactMapShellBox).not.toBeNull();
  expect(compactMapBoardBox!.y + compactMapBoardBox!.height).toBeLessThanOrEqual(720);
  expect(compactMapShellBox!.height).toBeGreaterThanOrEqual(280);

  await page.setViewportSize({ width: 1600, height: 900 });
  const mapBoardBox = await page.locator(".mapBoard").boundingBox();
  const mapShellBox = await page.locator(".mapShell").boundingBox();
  expect(mapBoardBox).not.toBeNull();
  expect(mapShellBox).not.toBeNull();
  expect(mapBoardBox!.y + mapBoardBox!.height).toBeLessThanOrEqual(900);
  expect(mapShellBox!.height).toBeGreaterThanOrEqual(360);

  await page.setViewportSize({ width: 1366, height: 768 });
  const laptopMapBoardBox = await page.locator(".mapBoard").boundingBox();
  const laptopMapShellBox = await page.locator(".mapShell").boundingBox();
  expect(laptopMapBoardBox).not.toBeNull();
  expect(laptopMapShellBox).not.toBeNull();
  expect(laptopMapBoardBox!.y + laptopMapBoardBox!.height).toBeLessThanOrEqual(768);
  expect(laptopMapShellBox!.height).toBeGreaterThanOrEqual(300);

  await expect(page.locator(".hero>div").first()).toContainText("실시간 운행00진행 중 전체 0건 · 위치 지연 0건모든 위치 최신");
  await expect(page.getByRole("button", { name: "전체 6", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByRole("button", { name: "진행 중 0", exact: true })).toHaveAttribute("aria-pressed", "false");
  await expect(page.getByLabel("선택한 차량")).toHaveValue(deliveries[0].id);
  await expect(page.getByLabel("선택한 차량").locator("option")).toHaveCount(6);
  await expect(page.locator(".focusStats")).toContainText("26.0 km");
  await expect(page.locator(".focusStats")).toContainText("TRUCK-01");
  const runtimeBadge=page.getByLabel("실행 환경 TEST 버전 0123456");
  await expect(runtimeBadge).toBeVisible();
  await expect(runtimeBadge).toHaveAttribute("aria-expanded","false");
  await runtimeBadge.click();
  await expect(runtimeBadge).toHaveAttribute("aria-expanded","true");
  const runtimeDetails=page.getByRole("complementary",{name:"실행 환경 상세",exact:true});
  await expect(runtimeDetails).toContainText("0123456789abcdef0123456789abcdef01234567");
  await expect(runtimeDetails).toContainText("환경별 데이터에 따라 다를 수 있습니다.");
  await page.keyboard.press("Escape");
  await expect(runtimeDetails).toBeHidden();
  const legendToggle = page.getByRole("button", { name: /지도 범례 6대 표시 보기/ });
  await expect(legendToggle).toHaveAttribute("aria-expanded", "false");
  await expect(page.getByText("실제 이동", { exact: true })).toBeHidden();
  await legendToggle.click();
  await expect(page.getByRole("button", { name: /지도 범례 6대 표시 접기/ })).toHaveAttribute("aria-expanded", "true");
  await expect(page.getByText("실제 이동", { exact: true })).toBeVisible();
  await expect(page.getByText("차량을 선택하면 상세 경로와 거점이 강조됩니다.")).toBeVisible();
  const expandMap=page.getByRole("button",{name:"지도 확대 보기"});
  await expandMap.click();
  await expect(page.locator(".mapShell")).toHaveClass(/mapExpanded/);
  await expect(page.getByRole("button",{name:"지도 원래 크기로"})).toHaveAttribute("aria-pressed","true");
  const expandedHud=page.getByRole("complementary",{name:"확대 지도 선택 차량 정보"});
  await expect(expandedHud).toContainText("TRUCK-01");
  await expect(expandedHud).toContainText("배송 완료");
  await expect(expandedHud).toContainText("출발지 1 → 도착지 1");
  await expect(expandedHud).toContainText("진행률100%");
  await expect(expandedHud).toContainText("최근 위치");
  await page.keyboard.press("Escape");
  await expect(expandedHud).toBeHidden();
  await expect(page.locator(".mapShell")).not.toHaveClass(/mapExpanded/);
  await page.setViewportSize({width:390,height:844});
  await expect(runtimeBadge.getByText("TEST",{exact:true})).toBeVisible();
});

test("prioritizes a searched vehicle beyond the fifty vehicle map limit", async ({ page }) => {
  await page.setViewportSize({ width: 1024, height: 768 });
  const denseDeliveries = createDenseDeliveries();

  await mockOverview(page, denseDeliveries);
  await page.goto("/console#overview");

  await expect(page.getByText("최근 50건을 지도에 표시합니다 · 검색하면 결과를 우선 표시합니다")).toBeVisible();
  await expect(page.getByRole("region", { name: /^50대의 차량 운행 지도/ })).toBeVisible();
  await expect(page.getByLabel("선택한 차량").locator("option")).toHaveCount(51);
  const tabletDenseMapBoardBox = await page.locator(".mapBoard").boundingBox();
  const tabletDenseMapShellBox = await page.locator(".mapShell").boundingBox();
  expect(tabletDenseMapBoardBox).not.toBeNull();
  expect(tabletDenseMapShellBox).not.toBeNull();
  expect(tabletDenseMapBoardBox!.y + tabletDenseMapBoardBox!.height).toBeLessThanOrEqual(768);
  expect(tabletDenseMapShellBox!.height).toBeGreaterThanOrEqual(280);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(1024);

  await page.setViewportSize({ width: 1280, height: 720 });
  const compactDenseMapBoardBox = await page.locator(".mapBoard").boundingBox();
  const compactDenseMapShellBox = await page.locator(".mapShell").boundingBox();
  expect(compactDenseMapBoardBox).not.toBeNull();
  expect(compactDenseMapShellBox).not.toBeNull();
  expect(compactDenseMapBoardBox!.y + compactDenseMapBoardBox!.height).toBeLessThanOrEqual(720);
  expect(compactDenseMapShellBox!.height).toBeGreaterThanOrEqual(280);

  await page.setViewportSize({ width: 1366, height: 768 });
  const denseMapBoardBox = await page.locator(".mapBoard").boundingBox();
  const denseMapShellBox = await page.locator(".mapShell").boundingBox();
  expect(denseMapBoardBox).not.toBeNull();
  expect(denseMapShellBox).not.toBeNull();
  expect(denseMapBoardBox!.y + denseMapBoardBox!.height).toBeLessThanOrEqual(768);
  expect(denseMapShellBox!.height).toBeGreaterThanOrEqual(300);

  await page.getByRole("searchbox", { name: "검색", exact: true }).fill("TRUCK-51");

  await expect(page.getByLabel("선택한 차량")).toHaveValue(denseDeliveries[50].id);
  await expect(page.getByLabel("선택한 차량").locator("option")).toHaveCount(1);
  await expect(page.locator(".focusStats")).toContainText("TRUCK-51");
  await expect(page.locator(".focusStats")).toContainText("76.0 km");
  await expect(page.getByRole("region", { name: /^1대의 차량 운행 지도/ })).toBeVisible();

  await page.getByRole("button", { name: "검색 지우기" }).click();

  await expect(page.getByLabel("선택한 차량")).toHaveValue(denseDeliveries[50].id);
  await expect(page.getByLabel("선택한 차량").locator("option")).toHaveCount(51);
  await expect(page.getByRole("region", { name: /^50대의 차량 운행 지도/ })).toBeVisible();
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

test("shows recovery guidance when fleet search has no results", async ({ page }) => {
  await mockOverview(page, deliveries);
  await page.goto("/console#overview");

  const search = page.getByRole("searchbox", { name: "검색", exact: true });
  await search.fill("TRUCK-99");

  await expect(page.getByText("0건", { exact: true })).toBeVisible();
  await expect(page.getByText("표시할 차량이 없습니다")).toBeVisible();
  await expect(page.getByText("“TRUCK-99” 검색 결과가 없습니다. 검색어를 지우거나 범위를 전환해 주세요.")).toBeVisible();
  await expect(page.getByLabel("선택한 차량")).toHaveCount(0);
  await expect(page.getByRole("region", { name: /^0대의 차량 운행 지도/ })).toBeVisible();

  await page.getByRole("button", { name: "검색 지우기" }).click();

  await expect(search).toHaveValue("");
  await expect(page.getByText("0건", { exact: true })).toHaveCount(0);
  await expect(page.getByLabel("선택한 차량")).toHaveValue(deliveries[0].id);
  await expect(page.getByLabel("선택한 차량").locator("option")).toHaveCount(6);
  await expect(page.locator(".focusStats")).toContainText("TRUCK-01");
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

  await expect(page.locator(".hero>div").first()).toContainText("실시간 운행00진행 중 전체 1건 · 위치 지연 1건지연 차량 확인 →");
  await expect(page.getByRole("button", { name: "진행 중 1", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByRole("button", { name: "전체 6", exact: true })).toHaveAttribute("aria-pressed", "false");
  await expect(page.getByLabel("선택한 차량")).toHaveValue(activeDeliveries[0].id);
  await expect(page.getByLabel("선택한 차량").locator("option")).toHaveCount(1);
  await expect(page.locator(".focusStats")).toContainText("26.0 km");
  await expect(page.locator(".focusStats")).toContainText("TRUCK-01");
});

test("defaults to recently reporting vehicles while keeping stale active deliveries accessible", async ({ page }) => {
  const activeDeliveries = deliveries.map((delivery, index) => index < 2 ? {
    ...delivery,
    status: "IN_TRANSIT",
    progress: index === 0 ? 0.25 : 0.75,
    eta: "2099-09-27T08:00:00Z",
    lastTelemetryAt: index === 0 ? "2099-09-27T07:59:30Z" : "2020-09-27T08:00:00Z",
  } : delivery);
  await mockOverview(page, activeDeliveries);

  await page.goto("/console#overview");

  await expect(page.getByRole("button", { name: "실시간 1", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByRole("button", { name: "진행 중 2", exact: true })).toHaveAttribute("aria-pressed", "false");
  await expect(page.locator(".hero>div").first()).toContainText("실시간 운행01진행 중 전체 2건 · 위치 지연 1건지연 차량 확인 →");
  await expect(page.locator(".hero>div").nth(2)).toContainText("평균 진행률25%최근 위치 수신 차량 기준");
  await expect(page.getByLabel("선택한 차량")).toHaveValue(activeDeliveries[0].id);
  await expect(page.getByLabel("선택한 차량").locator("option")).toHaveCount(1);

  await page.getByRole("button", { name: "진행 중 2", exact: true }).click();
  await expect(page.getByLabel("선택한 차량").locator("option")).toHaveCount(2);
  await page.getByRole("button", { name: "지연 차량 확인 →", exact: true }).click();
  await expect(page.getByRole("button", { name: "위치 지연 1", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByLabel("선택한 차량")).toHaveValue(activeDeliveries[1].id);
});

test("updates the selected vehicle from delivery and telemetry stream events", async ({ page }) => {
  const occurredAt = new Date().toISOString();
  const activeDeliveries = deliveries.map((delivery, index) => index === 0 ? {
    ...delivery,
    status: "IN_TRANSIT",
    currentLat: delivery.originLat + (delivery.destinationLat - delivery.originLat) * 0.2,
    currentLon: delivery.originLon + (delivery.destinationLon - delivery.originLon) * 0.2,
    progress: 0.2,
    eta: "2099-09-27T08:00:00Z",
    lastTelemetryAt: occurredAt,
  } : delivery);
  const updatedDelivery = {
    ...activeDeliveries[0],
    currentLat: activeDeliveries[0].originLat + (activeDeliveries[0].destinationLat - activeDeliveries[0].originLat) * 0.65,
    currentLon: activeDeliveries[0].originLon + (activeDeliveries[0].destinationLon - activeDeliveries[0].originLon) * 0.65,
    progress: 0.65,
    lastTelemetryAt: occurredAt,
  };
  const telemetryPoint = {
    eventId: "30000000-0000-4000-8000-000000000001",
    deliveryId: updatedDelivery.id,
    vehicleId: updatedDelivery.vehicleId,
    latitude: updatedDelivery.currentLat,
    longitude: updatedDelivery.currentLon,
    progress: updatedDelivery.progress,
    occurredAt,
  };
  const streamBody = [
    "event: connected\ndata: {}\n\n",
    `event: delivery-update\ndata: ${JSON.stringify(updatedDelivery)}\n\n`,
    `event: telemetry-point\ndata: ${JSON.stringify(telemetryPoint)}\n\n`,
  ].join("");

  await mockOverview(page, activeDeliveries, [], { body: streamBody, delayMs: 500 });
  await page.goto("/console#overview");

  await expect(page.getByLabel("선택한 차량")).toHaveValue(updatedDelivery.id);
  await expect(page.locator(".focusStats")).toContainText("진행률65%");

  await page.getByRole("link", { name: "주문·차량" }).click();
  await expect(page.getByRole("button", { name: /TRUCK-01.*65% 진행.*위치 방금 수신/ })).toBeVisible();
});

test("surfaces a new alert from the event stream across the attention views", async ({ page }) => {
  const occurredAt = new Date().toISOString();
  const activeDeliveries = deliveries.map((delivery, index) => index < 2 ? {
    ...delivery,
    status: "IN_TRANSIT",
    currentLat: (delivery.originLat + delivery.destinationLat) / 2,
    currentLon: (delivery.originLon + delivery.destinationLon) / 2,
    progress: 0.4 + index * 0.1,
    eta: "2099-09-27T08:00:00Z",
    lastTelemetryAt: occurredAt,
  } : delivery);
  const alert: DeliveryAlert = {
    id: "20000000-0000-4000-8000-000000000009",
    deliveryId: activeDeliveries[1].id,
    alertType: "ROUTE_DEVIATION",
    severity: "CRITICAL",
    status: "ACTIVE",
    message: "계획 경로에서 크게 벗어났습니다.",
    observedValue: 1_800,
    thresholdValue: 500,
    occurrenceCount: 2,
    firstObservedAt: occurredAt,
    lastObservedAt: occurredAt,
  };
  const streamBody = [
    "event: connected\ndata: {}\n\n",
    `event: alert-update\ndata: ${JSON.stringify(alert)}\n\n`,
  ].join("");

  await mockOverview(page, activeDeliveries, [], { body: streamBody, delayMs: 500 });
  await page.goto("/console#overview");

  await expect(page.getByText("현재 이상 없음")).toBeVisible();
  await expect(page.getByText("경고 1건")).toBeVisible();
  await expect(page.getByRole("button", { name: "확인 필요 1", exact: true })).toHaveAttribute("aria-pressed", "false");
  await expect(page.getByRole("button", { name: "TRUCK-02 주문 ORD-DEMO-2 출발지 2에서 도착지 2 지도에서 보기" })).toBeVisible();

  await page.getByRole("button", { name: "지도에서 확인 →" }).click();

  await expect(page.getByRole("button", { name: "확인 필요 1", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByLabel("선택한 차량")).toHaveValue(activeDeliveries[1].id);
  await expect(page.getByLabel("선택한 차량").locator("option")).toHaveCount(1);

  await page.getByRole("link", { name: "주문·차량" }).click();
  await expect(page.getByRole("button", { name: /TRUCK-02.*경고 1건/ })).toBeVisible();
  await expect(page.getByRole("button", { name: /TRUCK-01/ })).toHaveCount(0);
});

test("resolves an active alert from a later stream update", async ({ page }) => {
  const occurredAt = new Date().toISOString();
  const activeDeliveries = deliveries.map((delivery, index) => index < 2 ? {
    ...delivery,
    status: "IN_TRANSIT",
    currentLat: (delivery.originLat + delivery.destinationLat) / 2,
    currentLon: (delivery.originLon + delivery.destinationLon) / 2,
    progress: 0.4 + index * 0.1,
    eta: "2099-09-27T08:00:00Z",
    lastTelemetryAt: occurredAt,
  } : delivery);
  const activeAlert: DeliveryAlert = {
    id: "20000000-0000-4000-8000-000000000011",
    deliveryId: activeDeliveries[1].id,
    alertType: "ROUTE_DEVIATION",
    severity: "WARNING",
    status: "ACTIVE",
    message: "계획 경로에서 벗어났습니다.",
    observedValue: 750,
    thresholdValue: 500,
    occurrenceCount: 1,
    firstObservedAt: occurredAt,
    lastObservedAt: occurredAt,
  };
  const resolvedAlert: DeliveryAlert = {
    ...activeAlert,
    status: "RESOLVED",
    message: "계획 경로로 복귀했습니다.",
    observedValue: 180,
    resolvedAt: occurredAt,
  };

  await mockOverview(page, activeDeliveries, [activeAlert], {
    body: "event: connected\ndata: {}\n\n",
    bodiesByConnection: [
      `event: connected\ndata: {}\n\nevent: alert-update\ndata: ${JSON.stringify(activeAlert)}\n\n`,
      `event: connected\ndata: {}\n\nevent: alert-update\ndata: ${JSON.stringify(resolvedAlert)}\n\n`,
    ],
  });
  await page.goto("/console#overview");

  await expect(page.getByText("경고 1건")).toBeVisible();
  await expect(page.getByRole("button", { name: "확인 필요 1", exact: true })).toBeVisible();
  await expect(page.getByText("현재 이상 없음")).toBeVisible({ timeout: 10_000 });
  await expect(page.getByRole("button", { name: "확인 필요 0", exact: true })).toBeVisible();

  await page.getByRole("button", { name: "전체 이력 1" }).click();
  await expect(page.getByText("계획 경로로 복귀했습니다.")).toBeVisible();
  await expect(page.getByText(/해결됨/)).toBeVisible();
});

test("acknowledges an active alert with operator trace context", async ({ page }) => {
  const occurredAt = new Date().toISOString();
  const activeDeliveries = deliveries.map((delivery, index) => index === 0 ? {
    ...delivery,
    status: "IN_TRANSIT",
    currentLat: (delivery.originLat + delivery.destinationLat) / 2,
    currentLon: (delivery.originLon + delivery.destinationLon) / 2,
    progress: 0.5,
    eta: "2099-09-27T08:00:00Z",
    lastTelemetryAt: occurredAt,
  } : delivery);
  const activeAlert: DeliveryAlert = {
    id: "20000000-0000-4000-8000-000000000012",
    deliveryId: activeDeliveries[0].id,
    alertType: "DELAY",
    severity: "WARNING",
    status: "ACTIVE",
    message: "도착 예정 시각보다 지연되고 있습니다.",
    observedValue: 900,
    thresholdValue: 600,
    occurrenceCount: 1,
    firstObservedAt: occurredAt,
    lastObservedAt: occurredAt,
  };
  const acknowledgedAlert: DeliveryAlert = {
    ...activeAlert,
    acknowledgedAt: occurredAt,
    acknowledgedBy: "control-tower",
  };

  const requests = await mockOverview(page, activeDeliveries, [activeAlert], {
    body: "event: connected\ndata: {}\n\n",
    bodiesByConnection: ["event: connected\ndata: {}\n\n", "event: connected\ndata: {}\n\n"],
    alertRowsByRequest: [[activeAlert], [activeAlert], [acknowledgedAlert]],
    alertPageDelayAfterFirstLoadMs: 800,
    acknowledgementResponse: acknowledgedAlert,
  });
  await page.goto("/console#overview");

  await expect(page.locator(".alertHeaderStats")).toContainText("1미확인");
  await expect.poll(() => requests.alertRequestCount(), { timeout: 15_000 }).toBeGreaterThan(1);
  const acknowledgementButton = page.getByRole("button", { name: "TRUCK-01 주문 ORD-DEMO-1 출발지 1에서 도착지 1 경고 확인 처리" });
  await acknowledgementButton.evaluate(button => { (button as HTMLButtonElement).click(); (button as HTMLButtonElement).click(); });

  await expect(page.locator(".alertHeaderStats")).toContainText("0미확인");
  await expect(page.getByText(/확인 · control-tower/)).toBeVisible();
  await expect(page.getByRole("button", { name: /TRUCK-01.*경고 확인 처리/ })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "확인 필요 1", exact: true })).toBeVisible();
  expect(requests.acknowledgementRequestCount()).toBe(1);
  await page.waitForTimeout(1_000);
  await expect(page.getByText(/확인 · control-tower/)).toBeVisible();
});

test("recovers when alert acknowledgement initially fails", async ({ page }) => {
  const occurredAt = new Date().toISOString();
  const activeDeliveries = deliveries.map((delivery, index) => index === 0 ? {
    ...delivery,
    status: "IN_TRANSIT",
    currentLat: (delivery.originLat + delivery.destinationLat) / 2,
    currentLon: (delivery.originLon + delivery.destinationLon) / 2,
    progress: 0.5,
    eta: "2099-09-27T08:00:00Z",
    lastTelemetryAt: occurredAt,
  } : delivery);
  const activeAlert: DeliveryAlert = {
    id: "20000000-0000-4000-8000-000000000013",
    deliveryId: activeDeliveries[0].id,
    alertType: "ROUTE_DEVIATION",
    severity: "CRITICAL",
    status: "ACTIVE",
    message: "계획 경로에서 크게 벗어났습니다.",
    observedValue: 1_800,
    thresholdValue: 500,
    occurrenceCount: 2,
    firstObservedAt: occurredAt,
    lastObservedAt: occurredAt,
  };
  const acknowledgedAlert: DeliveryAlert = {
    ...activeAlert,
    acknowledgedAt: occurredAt,
    acknowledgedBy: "control-tower",
  };
  const acknowledgementButton = "TRUCK-01 주문 ORD-DEMO-1 출발지 1에서 도착지 1 경고 확인 처리";

  await mockOverview(page, activeDeliveries, [activeAlert], {
    body: "event: connected\ndata: {}\n\n",
    delayMs: 10_000,
    acknowledgementResponse: acknowledgedAlert,
    acknowledgementFailuresBeforeSuccess: 1,
  });
  await page.goto("/console#overview");

  await page.getByRole("button", { name: acknowledgementButton }).click();

  await expect(page.locator(".errorPanel")).toContainText("경고 확인 처리에 실패했습니다.");
  await expect(page.getByRole("button", { name: acknowledgementButton })).toBeEnabled();
  await expect(page.locator(".alertHeaderStats")).toContainText("1미확인");

  await page.getByRole("button", { name: acknowledgementButton }).click();

  await expect(page.locator(".errorPanel")).toHaveCount(0);
  await expect(page.locator(".alertHeaderStats")).toContainText("0미확인");
  await expect(page.getByText(/확인 · control-tower/)).toBeVisible();
});

test("accepts a streamed acknowledgement when the request later fails", async ({ page }) => {
  const occurredAt = new Date().toISOString();
  const activeDeliveries = deliveries.map((delivery, index) => index === 0 ? {
    ...delivery,
    status: "IN_TRANSIT",
    progress: 0.5,
    eta: "2099-09-27T08:00:00Z",
    lastTelemetryAt: occurredAt,
  } : delivery);
  const activeAlert: DeliveryAlert = {
    id: "20000000-0000-4000-8000-000000000015",
    deliveryId: activeDeliveries[0].id,
    alertType: "DELAY",
    severity: "WARNING",
    status: "ACTIVE",
    message: "도착 예정 시각보다 지연되고 있습니다.",
    observedValue: 900,
    thresholdValue: 600,
    occurrenceCount: 1,
    firstObservedAt: occurredAt,
    lastObservedAt: occurredAt,
  };
  const acknowledgedAlert: DeliveryAlert = {
    ...activeAlert,
    acknowledgedAt: occurredAt,
    acknowledgedBy: "control-tower",
  };

  const requests = await mockOverview(page, activeDeliveries, [activeAlert], {
    body: `event: connected\ndata: {}\n\nevent: alert-update\ndata: ${JSON.stringify(acknowledgedAlert)}\n\n`,
    acknowledgementResponse: acknowledgedAlert,
    acknowledgementFailuresBeforeSuccess: 1,
    acknowledgementDelayMs: 3_000,
    waitForAcknowledgementBeforeStream: true,
  });
  await page.goto("/console#overview");

  await page.getByRole("button", { name: "TRUCK-01 주문 ORD-DEMO-1 출발지 1에서 도착지 1 경고 확인 처리" }).click();

  await expect(page.getByText(/확인 · control-tower/)).toBeVisible();
  await expect.poll(() => requests.acknowledgementCompletedCount()).toBe(1);
  await expect(page.locator(".alertHeaderStats")).toContainText("0미확인");
  await expect(page.locator(".errorPanel")).toHaveCount(0);
});

test("clears a request failure when acknowledgement arrives from the stream", async ({ page }) => {
  const occurredAt = new Date().toISOString();
  const activeDeliveries = deliveries.map((delivery, index) => index === 0 ? {
    ...delivery,
    status: "IN_TRANSIT",
    progress: 0.5,
    eta: "2099-09-27T08:00:00Z",
    lastTelemetryAt: occurredAt,
  } : delivery);
  const activeAlert: DeliveryAlert = {
    id: "20000000-0000-4000-8000-000000000016",
    deliveryId: activeDeliveries[0].id,
    alertType: "DELAY",
    severity: "WARNING",
    status: "ACTIVE",
    message: "도착 예정 시각보다 지연되고 있습니다.",
    observedValue: 900,
    thresholdValue: 600,
    occurrenceCount: 1,
    firstObservedAt: occurredAt,
    lastObservedAt: occurredAt,
  };
  const acknowledgedAlert: DeliveryAlert = {
    ...activeAlert,
    acknowledgedAt: occurredAt,
    acknowledgedBy: "incident-lead",
  };

  await mockOverview(page, activeDeliveries, [activeAlert], {
    body: `event: connected\ndata: {}\n\nevent: alert-update\ndata: ${JSON.stringify(acknowledgedAlert)}\n\n`,
    acknowledgementResponse: acknowledgedAlert,
    acknowledgementFailuresBeforeSuccess: 1,
    waitForAcknowledgementBeforeStream: true,
    streamDelayAfterAcknowledgementMs: 1_000,
  });
  await page.goto("/console#overview");

  await page.getByRole("button", { name: "TRUCK-01 주문 ORD-DEMO-1 출발지 1에서 도착지 1 경고 확인 처리" }).click();

  await expect(page.locator(".errorPanel")).toContainText("경고 확인 처리에 실패했습니다.");
  await expect(page.getByText(/확인 · incident-lead/)).toBeVisible();
  await expect(page.locator(".errorPanel")).toHaveCount(0);
  await expect(page.locator(".alertHeaderStats")).toContainText("0미확인");
});

test("keeps another alert acknowledgement failure after a streamed recovery", async ({ page }) => {
  const occurredAt = new Date().toISOString();
  const activeDeliveries = deliveries.map((delivery, index) => index < 2 ? { ...delivery, status: "IN_TRANSIT", progress: 0.5, eta: "2099-09-27T08:00:00Z", lastTelemetryAt: occurredAt } : delivery);
  const activeAlerts: DeliveryAlert[] = activeDeliveries.slice(0, 2).map((delivery, index) => ({
    id: `20000000-0000-4000-8000-00000000003${index}`,
    deliveryId: delivery.id,
    alertType: index === 0 ? "DELAY" : "ROUTE_DEVIATION",
    severity: index === 0 ? "WARNING" : "CRITICAL",
    status: "ACTIVE",
    message: index === 0 ? "도착 예정 시각보다 지연되고 있습니다." : "계획 경로에서 크게 벗어났습니다.",
    observedValue: 900,
    thresholdValue: 600,
    occurrenceCount: 1,
    firstObservedAt: occurredAt,
    lastObservedAt: occurredAt,
  }));
  const streamedAcknowledgement: DeliveryAlert = { ...activeAlerts[1], acknowledgedAt: occurredAt, acknowledgedBy: "incident-lead" };
  const acknowledgementResponses = Object.fromEntries(activeAlerts.map(alert => [alert.id, { ...alert, acknowledgedAt: occurredAt, acknowledgedBy: "control-tower" }]));
  const firstButton = "TRUCK-01 주문 ORD-DEMO-1 출발지 1에서 도착지 1 경고 확인 처리";
  const secondButton = "TRUCK-02 주문 ORD-DEMO-2 출발지 2에서 도착지 2 경고 확인 처리";

  await mockOverview(page, activeDeliveries, activeAlerts, {
    body: `event: connected\ndata: {}\n\nevent: alert-update\ndata: ${JSON.stringify(streamedAcknowledgement)}\n\n`,
    acknowledgementResponses,
    acknowledgementFailuresBeforeSuccess: 2,
    waitForAcknowledgementCountBeforeStream: 2,
    streamDelayAfterAcknowledgementMs: 1_000,
  });
  await page.goto("/console#overview");

  await page.getByRole("button", { name: firstButton }).click();
  await page.getByRole("button", { name: secondButton }).click();

  await expect(page.getByText(/확인 · incident-lead/)).toBeVisible();
  await expect(page.getByRole("button", { name: firstButton })).toBeEnabled();
  await expect(page.locator(".errorPanel")).toContainText("경고 확인 처리에 실패했습니다.");
});

test("preserves a resolved stream update while acknowledgement is pending", async ({ page }) => {
  const occurredAt = new Date().toISOString();
  const activeDeliveries = deliveries.map((delivery, index) => index === 0 ? {
    ...delivery,
    status: "IN_TRANSIT",
    currentLat: (delivery.originLat + delivery.destinationLat) / 2,
    currentLon: (delivery.originLon + delivery.destinationLon) / 2,
    progress: 0.5,
    eta: "2099-09-27T08:00:00Z",
    lastTelemetryAt: occurredAt,
  } : delivery);
  const activeAlert: DeliveryAlert = {
    id: "20000000-0000-4000-8000-000000000014",
    deliveryId: activeDeliveries[0].id,
    alertType: "ROUTE_DEVIATION",
    severity: "CRITICAL",
    status: "ACTIVE",
    message: "계획 경로에서 크게 벗어났습니다.",
    observedValue: 1_800,
    thresholdValue: 500,
    occurrenceCount: 2,
    firstObservedAt: occurredAt,
    lastObservedAt: occurredAt,
  };
  const acknowledgedAlert: DeliveryAlert = {
    ...activeAlert,
    acknowledgedAt: occurredAt,
    acknowledgedBy: "control-tower",
  };
  const resolvedAlert: DeliveryAlert = {
    ...activeAlert,
    status: "RESOLVED",
    message: "계획 경로로 복귀했습니다.",
    resolvedAt: occurredAt,
    acknowledgedAt: occurredAt,
    acknowledgedBy: "incident-lead",
  };

  await mockOverview(page, activeDeliveries, [activeAlert], {
    body: `event: connected\ndata: {}\n\nevent: alert-update\ndata: ${JSON.stringify(resolvedAlert)}\n\n`,
    acknowledgementResponse: acknowledgedAlert,
    acknowledgementDelayMs: 500,
    waitForAcknowledgementBeforeStream: true,
  });
  await page.goto("/console#overview");

  await page.getByRole("button", { name: "TRUCK-01 주문 ORD-DEMO-1 출발지 1에서 도착지 1 경고 확인 처리" }).click();

  await expect(page.getByText("현재 이상 없음")).toBeVisible();
  await page.getByRole("button", { name: "전체 이력 1" }).click();
  await expect(page.getByText("계획 경로로 복귀했습니다.")).toBeVisible();
  await expect(page.getByText(/해결됨/)).toBeVisible();
  await expect(page.getByText(/확인 · incident-lead/)).toBeVisible();
});

test("tracks concurrent alert acknowledgements independently", async ({ page }) => {
  const occurredAt = new Date().toISOString();
  const activeDeliveries = deliveries.map((delivery, index) => index < 2 ? {
    ...delivery,
    status: "IN_TRANSIT",
    currentLat: (delivery.originLat + delivery.destinationLat) / 2,
    currentLon: (delivery.originLon + delivery.destinationLon) / 2,
    progress: 0.5,
    eta: "2099-09-27T08:00:00Z",
    lastTelemetryAt: occurredAt,
  } : delivery);
  const activeAlerts: DeliveryAlert[] = activeDeliveries.slice(0, 2).map((delivery, index) => ({
    id: `20000000-0000-4000-8000-00000000002${index}`,
    deliveryId: delivery.id,
    alertType: index === 0 ? "DELAY" : "ROUTE_DEVIATION",
    severity: index === 0 ? "WARNING" : "CRITICAL",
    status: "ACTIVE",
    message: index === 0 ? "도착 예정 시각보다 지연되고 있습니다." : "계획 경로에서 크게 벗어났습니다.",
    observedValue: 900,
    thresholdValue: 600,
    occurrenceCount: 1,
    firstObservedAt: occurredAt,
    lastObservedAt: occurredAt,
  }));
  const acknowledgementResponses = Object.fromEntries(activeAlerts.map(alert => [alert.id, {
    ...alert,
    acknowledgedAt: occurredAt,
    acknowledgedBy: "control-tower",
  }]));
  const firstButton = "TRUCK-01 주문 ORD-DEMO-1 출발지 1에서 도착지 1 경고 확인 처리";
  const secondButton = "TRUCK-02 주문 ORD-DEMO-2 출발지 2에서 도착지 2 경고 확인 처리";

  await mockOverview(page, activeDeliveries, activeAlerts, {
    body: "event: connected\ndata: {}\n\n",
    delayMs: 10_000,
    acknowledgementResponses,
    acknowledgementDelayMsById: {
      [activeAlerts[0].id]: 300,
      [activeAlerts[1].id]: 1_200,
    },
  });
  await page.goto("/console#overview");

  await page.getByRole("button", { name: firstButton }).click();
  await page.getByRole("button", { name: secondButton }).click();

  await expect(page.getByRole("button", { name: firstButton })).toHaveCount(0);
  await expect(page.getByRole("button", { name: secondButton })).toBeDisabled();
  await expect(page.getByRole("button", { name: secondButton })).toHaveText("확인 처리 중…");
  await expect(page.locator(".alertHeaderStats")).toContainText("1미확인");

  await expect(page.getByRole("button", { name: secondButton })).toHaveCount(0);
  await expect(page.locator(".alertHeaderStats")).toContainText("0미확인");
  await expect(page.getByText(/확인 · control-tower/)).toHaveCount(2);
});

test("resynchronizes deliveries after the event stream reconnects", async ({ page }) => {
  const activeDeliveries = deliveries.map((delivery, index) => index === 0 ? {
    ...delivery,
    status: "IN_TRANSIT",
    currentLat: delivery.originLat + (delivery.destinationLat - delivery.originLat) * 0.2,
    currentLon: delivery.originLon + (delivery.destinationLon - delivery.originLon) * 0.2,
    progress: 0.2,
    eta: "2099-09-27T08:00:00Z",
    lastTelemetryAt: new Date().toISOString(),
  } : delivery);
  const resynchronizedDeliveries = activeDeliveries.map((delivery, index) => index === 0 ? {
    ...delivery,
    currentLat: delivery.originLat + (delivery.destinationLat - delivery.originLat) * 0.8,
    currentLon: delivery.originLon + (delivery.destinationLon - delivery.originLon) * 0.8,
    progress: 0.8,
  } : delivery);

  await mockOverview(page, activeDeliveries, [], {
    body: "event: connected\ndata: {}\n\n",
    deliveryRowsAfterFirstLoad: resynchronizedDeliveries,
  });
  await page.goto("/console#overview");

  await expect(page.locator(".focusStats")).toContainText("진행률20%");
  await expect(page.locator(".focusStats")).toContainText("진행률80%", { timeout: 10_000 });
  await expect(page.getByLabel("선택한 차량")).toHaveValue(resynchronizedDeliveries[0].id);
});

test("resynchronizes route and telemetry snapshots after the event stream reconnects", async ({ page }) => {
  const occurredAt = new Date().toISOString();
  const activeDeliveries = deliveries.map((delivery, index) => index === 0 ? {
    ...delivery,
    status: "IN_TRANSIT",
    currentLat: (delivery.originLat + delivery.destinationLat) / 2,
    currentLon: (delivery.originLon + delivery.destinationLon) / 2,
    progress: 0.5,
    eta: "2099-09-27T08:00:00Z",
    lastTelemetryAt: "2000-01-01T00:00:00Z",
  } : delivery);
  const initialTelemetry: TelemetryPoint = {
    eventId: "30000000-0000-4000-8000-000000000011",
    deliveryId: activeDeliveries[0].id,
    vehicleId: activeDeliveries[0].vehicleId,
    latitude: activeDeliveries[0].originLat,
    longitude: activeDeliveries[0].originLon,
    progress: 0.1,
    occurredAt: "2000-01-01T00:00:00Z",
  };
  const resynchronizedTelemetry: TelemetryPoint = {
    ...initialTelemetry,
    eventId: "30000000-0000-4000-8000-000000000012",
    latitude: activeDeliveries[0].currentLat,
    longitude: activeDeliveries[0].currentLon,
    progress: 0.5,
    occurredAt,
  };

  await mockOverview(page, activeDeliveries, [], {
    body: "event: connected\ndata: {}\n\n",
    routeDistanceMetersAfterFirstLoad: 86_000,
    telemetryRows: [initialTelemetry],
    telemetryRowsAfterFirstLoad: [resynchronizedTelemetry],
  });
  await page.goto("/console#overview");

  await expect(page.locator(".focusStats")).toContainText("26.0 km");
  await expect(page.locator(".focusStats")).toContainText("86.0 km", { timeout: 10_000 });

  await page.getByRole("link", { name: "주문·차량" }).click();
  await expect(page.getByRole("button", { name: /TRUCK-01.*위치 방금 수신/ })).toBeVisible();
});

test("resynchronizes resolved alerts after the event stream reconnects", async ({ page }) => {
  const occurredAt = new Date().toISOString();
  const activeDeliveries = deliveries.map((delivery, index) => index < 2 ? {
    ...delivery,
    status: "IN_TRANSIT",
    currentLat: (delivery.originLat + delivery.destinationLat) / 2,
    currentLon: (delivery.originLon + delivery.destinationLon) / 2,
    progress: 0.4 + index * 0.1,
    eta: "2099-09-27T08:00:00Z",
    lastTelemetryAt: occurredAt,
  } : delivery);
  const activeAlert: DeliveryAlert = {
    id: "20000000-0000-4000-8000-000000000010",
    deliveryId: activeDeliveries[1].id,
    alertType: "DELAY",
    severity: "WARNING",
    status: "ACTIVE",
    message: "도착 예정 시각보다 지연되고 있습니다.",
    observedValue: 900,
    thresholdValue: 600,
    occurrenceCount: 1,
    firstObservedAt: occurredAt,
    lastObservedAt: occurredAt,
  };
  const resolvedAlert: DeliveryAlert = {
    ...activeAlert,
    status: "RESOLVED",
    message: "도착 지연이 해소되었습니다.",
    observedValue: 240,
    resolvedAt: occurredAt,
  };

  await mockOverview(page, activeDeliveries, [activeAlert], {
    body: "event: connected\ndata: {}\n\n",
    alertRowsAfterFirstLoad: [resolvedAlert],
  });
  await page.goto("/console#overview");

  await expect(page.getByText("경고 1건")).toBeVisible();
  await expect(page.getByRole("button", { name: "확인 필요 1", exact: true })).toBeVisible();
  await expect(page.getByText("현재 이상 없음")).toBeVisible({ timeout: 10_000 });
  await expect(page.getByRole("button", { name: "확인 필요 0", exact: true })).toBeVisible();
  await expect(page.getByText("경고 1건")).toHaveCount(0);

  await page.getByRole("button", { name: "전체 이력 1" }).click();
  await expect(page.getByText("도착 지연이 해소되었습니다.")).toBeVisible();
  await expect(page.getByText(/해결됨/)).toBeVisible();
});

test("focuses the alerted vehicle from the attention summary", async ({ page }) => {
  const activeDeliveries = deliveries.map((delivery, index) => index < 2 ? {
    ...delivery,
    status: "IN_TRANSIT",
    currentLat: (delivery.originLat + delivery.destinationLat) / 2,
    currentLon: (delivery.originLon + delivery.destinationLon) / 2,
    progress: 0.4 + index * 0.1,
    eta: "2099-09-27T08:00:00Z",
    lastTelemetryAt: "2099-09-27T07:55:00Z",
  } : delivery);
  const alert: DeliveryAlert = {
    id: "20000000-0000-4000-8000-000000000001",
    deliveryId: activeDeliveries[1].id,
    alertType: "ROUTE_DEVIATION",
    severity: "WARNING",
    status: "ACTIVE",
    message: "계획 경로에서 벗어났습니다.",
    observedValue: 700,
    thresholdValue: 500,
    occurrenceCount: 1,
    firstObservedAt: now,
    lastObservedAt: now,
  };

  await mockOverview(page, activeDeliveries, [alert]);
  await page.goto("/console#overview");

  await expect(page.getByRole("button", { name: "실시간 2", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByLabel("선택한 차량").locator("option")).toHaveCount(2);
  await expect(page.getByRole("button", { name: "지도에서 확인 →" })).toBeVisible();

  await page.getByRole("button", { name: "지도에서 확인 →" }).click();

  await expect(page.getByRole("button", { name: "확인 필요 1", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByRole("button", { name: "진행 중 2", exact: true })).toHaveAttribute("aria-pressed", "false");
  await expect(page.getByLabel("선택한 차량")).toHaveValue(activeDeliveries[1].id);
  await expect(page.getByLabel("선택한 차량").locator("option")).toHaveCount(1);
  await expect(page.locator(".focusStats")).toContainText("TRUCK-02");
});

test("filters active vehicles to the stale telemetry scope", async ({ page }) => {
  const activeDeliveries = deliveries.map((delivery, index) => index < 2 ? {
    ...delivery,
    status: "IN_TRANSIT",
    currentLat: (delivery.originLat + delivery.destinationLat) / 2,
    currentLon: (delivery.originLon + delivery.destinationLon) / 2,
    progress: 0.4 + index * 0.1,
    eta: "2099-09-27T08:00:00Z",
    lastTelemetryAt: index === 0 ? "2099-09-27T07:55:00Z" : "2000-01-01T00:00:00Z",
  } : delivery);

  await mockOverview(page, activeDeliveries);
  await page.goto("/console#overview");

  await expect(page.getByRole("button", { name: "실시간 1", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByRole("button", { name: "위치 지연 1", exact: true })).toHaveAttribute("aria-pressed", "false");
  await expect(page.getByLabel("선택한 차량").locator("option")).toHaveCount(1);

  await page.getByRole("button", { name: "위치 지연 1", exact: true }).click();

  await expect(page.getByRole("button", { name: "위치 지연 1", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByRole("button", { name: "진행 중 2", exact: true })).toHaveAttribute("aria-pressed", "false");
  await expect(page.getByLabel("선택한 차량")).toHaveValue(activeDeliveries[1].id);
  await expect(page.getByLabel("선택한 차량").locator("option")).toHaveCount(1);
  await expect(page.locator(".focusStats")).toContainText("TRUCK-02");
  await expect(page.locator(".focusStats")).toContainText("운송 중");
  await expect(page.locator(".focusStats")).toContainText("최근 위치24시간 이상위치 지연");

  await page.getByRole("link", { name: "주문·차량" }).click();
  await expect(page.getByRole("button", { name: "위치 지연 1", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByText("1 / 1건 표시 · 전체 6건")).toBeVisible();
  await expect(page.getByRole("button", { name: /TRUCK-02/ })).toBeVisible();
  await expect(page.getByRole("button", { name: /TRUCK-01/ })).toHaveCount(0);
});

test("focuses an overdue vehicle even when it has no active alert", async ({ page }) => {
  const activeDeliveries = deliveries.map((delivery, index) => index < 2 ? {
    ...delivery,
    status: "IN_TRANSIT",
    currentLat: (delivery.originLat + delivery.destinationLat) / 2,
    currentLon: (delivery.originLon + delivery.destinationLon) / 2,
    progress: 0.4 + index * 0.1,
    eta: index === 0 ? "2099-09-27T08:00:00Z" : "2000-01-01T00:00:00Z",
    lastTelemetryAt: "2099-09-27T07:55:00Z",
  } : delivery);

  await mockOverview(page, activeDeliveries);
  await page.goto("/console#overview");

  await expect(page.getByText("예정 초과 1건", { exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "확인 필요 1", exact: true })).toHaveAttribute("aria-pressed", "false");
  await expect(page.getByRole("button", { name: "지도에서 확인 →" })).toBeVisible();

  await page.getByRole("button", { name: "지도에서 확인 →" }).click();

  await expect(page.getByRole("button", { name: "확인 필요 1", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByLabel("선택한 차량")).toHaveValue(activeDeliveries[1].id);
  await expect(page.getByLabel("선택한 차량").locator("option")).toHaveCount(1);
  await expect(page.locator(".focusStats")).toContainText("TRUCK-02");
  await expect(page.locator(".focusStats .etaOverdue")).toContainText("예정 초과");
  await expect(page.getByRole("region", { name: /예정 초과 1대/ })).toBeVisible();
});

test("counts a vehicle with an alert and overdue ETA only once", async ({ page }) => {
  const activeDeliveries = deliveries.map((delivery, index) => index < 2 ? {
    ...delivery,
    status: "IN_TRANSIT",
    currentLat: (delivery.originLat + delivery.destinationLat) / 2,
    currentLon: (delivery.originLon + delivery.destinationLon) / 2,
    progress: 0.4 + index * 0.1,
    eta: index === 0 ? "2099-09-27T08:00:00Z" : "2000-01-01T00:00:00Z",
    lastTelemetryAt: "2099-09-27T07:55:00Z",
  } : delivery);
  const alert: DeliveryAlert = {
    id: "20000000-0000-4000-8000-000000000002",
    deliveryId: activeDeliveries[1].id,
    alertType: "DELAY",
    severity: "CRITICAL",
    status: "ACTIVE",
    message: "예정 도착 시각을 초과했습니다.",
    observedValue: 1_800,
    thresholdValue: 600,
    occurrenceCount: 2,
    firstObservedAt: now,
    lastObservedAt: now,
  };

  await mockOverview(page, activeDeliveries, [alert]);
  await page.goto("/console#overview");

  await expect(page.getByText("경고 1 · 예정 초과 1", { exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "확인 필요 1", exact: true })).toHaveAttribute("aria-pressed", "false");

  await page.getByRole("button", { name: "지도에서 확인 →" }).click();

  await expect(page.getByRole("button", { name: "확인 필요 1", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByLabel("선택한 차량")).toHaveValue(activeDeliveries[1].id);
  await expect(page.getByLabel("선택한 차량").locator("option")).toHaveCount(1);
  await expect(page.locator(".focusStats")).toContainText("TRUCK-02");
  await expect(page.locator(".focusStats .etaOverdue")).toContainText("예정 초과");
});

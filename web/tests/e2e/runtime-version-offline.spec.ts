import { expect, test } from "@playwright/test";

test("pauses runtime version polling offline and checks immediately after reconnecting",async({page,context})=>{
  const requests:string[]=[];
  await page.route("**/api/runtime-version",async route=>{
    requests.push(route.request().url());
    await route.fulfill({
      contentType:"application/json",
      json:{version:"test-version",revision:"2fa00e29adb3a8fa6124230330b8848bf735dab0",builtAt:"2026-10-02T00:00:00Z",environment:"test"},
    });
  });

  await page.goto("/login");
  await expect(page.getByRole("button",{name:"실행 환경 TEST 버전 2fa00e2"})).toBeVisible();
  expect(requests).toHaveLength(1);

  await context.setOffline(true);
  await page.waitForTimeout(16_000);
  expect(requests).toHaveLength(1);

  await context.setOffline(false);
  await expect.poll(()=>requests.length).toBe(2);
});

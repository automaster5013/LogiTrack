import unittest
from datetime import datetime, timezone
from types import SimpleNamespace

from app.reporting import render_daily_kpi_report


class ReportingTest(unittest.TestCase):
    def test_renders_summary_and_detail_pages(self):
        rows = [SimpleNamespace(
            metricDate=f"2026-09-{day:02d}", totalDeliveries=day,
            activeDeliveries=2, deliveredDeliveries=max(0, day - 2), delayedDeliveries=1,
            averageProgressPercent=76.25, averageCycleMinutes=48.5,
            onTimeRatePercent=94.2, projectedAt=datetime.now(timezone.utc),
        ) for day in range(1, 31)]

        result = render_daily_kpi_report(rows)

        self.assertTrue(result.startswith(b"%PDF-"))
        self.assertGreater(len(result), 5_000)
        self.assertEqual(result.count(b"/Type /Page\n"), 2)


if __name__ == "__main__":
    unittest.main()

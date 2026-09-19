import unittest

from fastapi.testclient import TestClient

from app.main import app


class ApiBoundaryTest(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.row = {
            "metricDate": "2026-09-20", "totalDeliveries": 10, "activeDeliveries": 2,
            "deliveredDeliveries": 8, "delayedDeliveries": 1, "averageProgressPercent": 75.5,
            "averageCycleMinutes": 42.0, "onTimeRatePercent": 95.0,
            "projectedAt": "2026-09-20T12:00:00Z",
        }

    def test_pdf_rows_are_bounded(self):
        self.assertEqual(422, self.client.post("/reports/daily-kpis.pdf", json=[]).status_code)
        self.assertEqual(422, self.client.post("/reports/daily-kpis.pdf", json=[self.row] * 91).status_code)

    def test_pdf_metrics_are_bounded(self):
        invalid = dict(self.row, averageProgressPercent=101)
        self.assertEqual(422, self.client.post("/reports/daily-kpis.pdf", json=[invalid]).status_code)

    def test_oversized_raw_body_is_rejected_before_validation(self):
        response = self.client.post("/reports/daily-kpis.pdf", content=b" " * (2 * 1024 * 1024 + 1), headers={"Content-Type": "application/json"})
        self.assertEqual(413, response.status_code)
        self.assertEqual("Request body is too large", response.json()["detail"])

    def test_valid_pdf_is_rendered(self):
        response = self.client.post("/reports/daily-kpis.pdf", json=[self.row])
        self.assertEqual(200, response.status_code)
        self.assertEqual("application/pdf", response.headers["content-type"])
        self.assertTrue(response.content.startswith(b"%PDF-"))


if __name__ == "__main__":
    unittest.main()

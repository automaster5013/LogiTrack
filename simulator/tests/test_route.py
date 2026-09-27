import sys
import unittest
import uuid
from unittest import mock
from pathlib import Path
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).parents[1]))
from logitrack_sim.route import Point, distance_km, interpolate, planned_eta, sample_route
from logitrack_sim import main
from logitrack_sim.main import mark_healthy, pending_step_indexes, simulation_start_state, telemetry_event_id, validate_config
from datetime import datetime, timezone


class RouteTest(unittest.TestCase):

    def test_telemetry_event_ids_are_stable_per_delivery_event_step(self):
        delivery_event_id = "8c9bf7fe-25f0-4d08-9a88-69dd4f1ad051"
        first = telemetry_event_id(delivery_event_id, 1)
        self.assertEqual(first, telemetry_event_id(delivery_event_id, 1))
        self.assertNotEqual(first, telemetry_event_id(delivery_event_id, 2))
        self.assertEqual(5, uuid.UUID(first).version)

    def test_staging_can_start_new_delivery_without_authenticated_api_read(self):
        original = main.RESUME_FROM_API
        try:
            main.RESUME_FROM_API = "false"
            with mock.patch.object(main, "load_delivery_state") as loader:
                self.assertEqual((0.0, "CREATED"), simulation_start_state("delivery-1"))
                loader.assert_not_called()
        finally:
            main.RESUME_FROM_API = original
    def test_mark_healthy_creates_and_refreshes_heartbeat(self):
        with TemporaryDirectory() as directory:
            heartbeat = Path(directory) / "simulator-heartbeat"
            mark_healthy(heartbeat)
            first_modified = heartbeat.stat().st_mtime_ns
            mark_healthy(heartbeat)
            self.assertTrue(heartbeat.is_file())
            self.assertGreaterEqual(heartbeat.stat().st_mtime_ns, first_modified)

    def test_interpolation_reaches_destination(self):
        destination = Point(37.4563, 126.7052)
        route = interpolate(Point(37.5665, 126.9780), destination, 10)
        self.assertEqual(10, len(route))
        self.assertAlmostEqual(destination.lat, route[-1].lat)
        self.assertAlmostEqual(destination.lon, route[-1].lon)

    def test_distance_is_reasonable(self):
        km = distance_km(Point(37.5665, 126.9780), Point(37.4563, 126.7052))
        self.assertGreater(km, 20)
        self.assertLess(km, 40)

    def test_rejects_invalid_steps(self):
        with self.assertRaises(ValueError): interpolate(Point(0, 0), Point(1, 1), 1)

    def test_samples_polyline_by_traveled_distance(self):
        route = [Point(0, 0), Point(0, 2), Point(1, 2)]
        sampled = sample_route(route, 3)
        self.assertEqual(3, len(sampled))
        self.assertAlmostEqual(2, sampled[-1].lon)
        self.assertAlmostEqual(1, sampled[-1].lat)
        self.assertAlmostEqual(0, sampled[0].lat, places=2)

    def test_planned_eta_uses_remaining_route_duration(self):
        before = datetime.now(timezone.utc).timestamp()
        value = datetime.fromisoformat(planned_eta(1000, 0.25).replace("Z", "+00:00")).timestamp()
        self.assertGreaterEqual(value - before, 749)
        self.assertLessEqual(value - before, 751)

    def test_rejects_resource_exhausting_simulator_configuration(self):
        validate_config(1, 20, 8)
        for values in [(0, 20, 8), (1, 1, 8), (1, 20, 0), (1, 1000, 8)]:
            with self.assertRaises(ValueError): validate_config(*values)

    def test_resumes_after_the_last_applied_progress_step(self):
        self.assertEqual(list(range(1, 21)), pending_step_indexes(0, 20))
        self.assertEqual([19, 20], pending_step_indexes(0.9, 20))
        self.assertEqual([], pending_step_indexes(1, 20))


if __name__ == "__main__": unittest.main()

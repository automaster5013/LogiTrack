import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1]))
from logitrack_sim.route import Point, distance_km, interpolate, planned_eta, sample_route
from datetime import datetime, timezone


class RouteTest(unittest.TestCase):
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


if __name__ == "__main__": unittest.main()

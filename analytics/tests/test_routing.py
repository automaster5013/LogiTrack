import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1]))
from app.routing import Coordinate, geodesic_fallback, parse_osrm
from app.routing import RoutePlanner


class RoutingTest(unittest.TestCase):
    def test_fallback_is_deterministic_and_complete(self):
        origin, destination = Coordinate(37.5665, 126.978), Coordinate(37.4563, 126.7052)
        first = geodesic_fallback(origin, destination)
        second = geodesic_fallback(origin, destination)
        self.assertEqual(first.geometry_hash, second.geometry_hash)
        self.assertEqual([origin.lon, origin.lat], first.coordinates[0])
        self.assertEqual([destination.lon, destination.lat], first.coordinates[-1])
        self.assertGreater(first.distance_meters, 20_000)
        self.assertGreater(first.duration_seconds, 0)

    def test_parses_osrm_geojson(self):
        route = parse_osrm({"code":"Ok","routes":[{"distance":1234.4,"duration":90.2,
            "geometry":{"coordinates":[[126.9,37.5],[127.0,37.6]]}}]})
        self.assertEqual("osrm", route.provider)
        self.assertEqual(1234, route.distance_meters)
        self.assertEqual(90, route.duration_seconds)

    def test_rejects_empty_osrm_route(self):
        with self.assertRaises(ValueError):
            parse_osrm({"code":"NoRoute","routes":[]})


class RoutePlannerCacheTest(unittest.IsolatedAsyncioTestCase):
    async def test_reuses_route_for_identical_coordinates(self):
        planner = RoutePlanner("geodesic", "http://unused", cache_ttl_seconds=300)
        origin = Coordinate(37.5665, 126.978)
        destination = Coordinate(37.4563, 126.7052)

        first = await planner.plan(origin, destination)
        second = await planner.plan(origin, destination)

        self.assertIs(first, second)


if __name__ == "__main__": unittest.main()

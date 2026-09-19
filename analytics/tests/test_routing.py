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

    def test_rejects_invalid_osrm_values(self):
        for distance, duration, coordinates in [
            (-1, 30, [[126.9,37.5],[127.0,37.6]]),
            (100, float("inf"), [[126.9,37.5],[127.0,37.6]]),
            (100, 30, [[999,37.5],[127.0,37.6]]),
            (100, 30, [[126.9,float("nan")],[127.0,37.6]]),
        ]:
            with self.assertRaises(ValueError):
                parse_osrm({"code":"Ok","routes":[{"distance":distance,"duration":duration,"geometry":{"coordinates":coordinates}}]})


class RoutePlannerCacheTest(unittest.IsolatedAsyncioTestCase):
    async def test_rejects_unsafe_client_configuration(self):
        with self.assertRaises(ValueError): RoutePlanner("typo", "http://localhost")
        with self.assertRaises(ValueError): RoutePlanner("osrm", "http://localhost", timeout_seconds=0)
        with self.assertRaises(ValueError): RoutePlanner("osrm", "http://localhost", cache_ttl_seconds=86_401)

    async def test_reuses_route_for_identical_coordinates(self):
        planner = RoutePlanner("geodesic", "http://unused", cache_ttl_seconds=300)
        origin = Coordinate(37.5665, 126.978)
        destination = Coordinate(37.4563, 126.7052)

        first = await planner.plan(origin, destination)
        second = await planner.plan(origin, destination)

        self.assertIs(first, second)

    async def test_cache_is_bounded_without_full_flush(self):
        planner = RoutePlanner("geodesic", "http://unused", cache_ttl_seconds=300)
        for index in range(1025):
            await planner.plan(Coordinate(0, index / 10_000), Coordinate(1, 1))
        self.assertEqual(1024, len(planner._cache))
        self.assertNotIn((0, 0.0, 1, 1), planner._cache)
        self.assertIn((0, 0.1024, 1, 1), planner._cache)

    async def test_zero_ttl_disables_cache(self):
        planner = RoutePlanner("geodesic", "http://unused", cache_ttl_seconds=0)
        await planner.plan(Coordinate(0, 0), Coordinate(1, 1))
        self.assertEqual(0, len(planner._cache))


if __name__ == "__main__": unittest.main()

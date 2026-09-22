import sys
import unittest
import asyncio
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

    def test_zero_length_fallback_remains_persistable(self):
        point = Coordinate(37.5, 127.0)
        result = geodesic_fallback(point, point)
        self.assertEqual(1, result.distance_meters)
        self.assertGreater(result.duration_seconds, 0)

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

    async def test_deduplicates_identical_inflight_requests(self):
        planner = RoutePlanner("geodesic", "http://unused", cache_ttl_seconds=0)
        calls = 0
        async def fake(origin, destination):
            nonlocal calls
            calls += 1
            await asyncio.sleep(0.02)
            return geodesic_fallback(origin, destination)
        planner._plan_uncached = fake
        origin, destination = Coordinate(0, 0), Coordinate(1, 1)
        await asyncio.gather(planner.plan(origin, destination), planner.plan(origin, destination))
        self.assertEqual(1, calls)

    async def test_processes_different_routes_concurrently(self):
        planner = RoutePlanner("geodesic", "http://unused", cache_ttl_seconds=0)
        active = peak = 0
        async def fake(origin, destination):
            nonlocal active, peak
            active += 1; peak = max(peak, active)
            await asyncio.sleep(0.02)
            active -= 1
            return geodesic_fallback(origin, destination)
        planner._plan_uncached = fake
        await asyncio.gather(planner.plan(Coordinate(0, 0), Coordinate(1, 1)), planner.plan(Coordinate(0, 0.1), Coordinate(1, 1)))
        self.assertEqual(2, peak)

    async def test_cancelled_waiter_does_not_cancel_shared_route(self):
        planner = RoutePlanner("geodesic", "http://unused", cache_ttl_seconds=0)
        async def fake(origin, destination):
            await asyncio.sleep(0.03)
            return geodesic_fallback(origin, destination)
        planner._plan_uncached = fake
        origin, destination = Coordinate(0, 0), Coordinate(1, 1)
        cancelled = asyncio.create_task(planner.plan(origin, destination))
        survivor = asyncio.create_task(planner.plan(origin, destination))
        await asyncio.sleep(0.005);cancelled.cancel()
        with self.assertRaises(asyncio.CancelledError): await cancelled
        self.assertEqual("geodesic-fallback",(await survivor).provider)

    async def test_abandoned_route_is_finalized(self):
        planner = RoutePlanner("geodesic", "http://unused", cache_ttl_seconds=300)
        async def fake(origin, destination):
            await asyncio.sleep(0.02)
            return geodesic_fallback(origin, destination)
        planner._plan_uncached = fake
        request=asyncio.create_task(planner.plan(Coordinate(0,0),Coordinate(1,1)))
        await asyncio.sleep(0.005);request.cancel()
        with self.assertRaises(asyncio.CancelledError): await request
        for _ in range(40):
            if not planner._inflight and len(planner._cache) == 1:
                break
            await asyncio.sleep(0.005)
        self.assertEqual(0,len(planner._inflight));self.assertEqual(1,len(planner._cache))


if __name__ == "__main__": unittest.main()

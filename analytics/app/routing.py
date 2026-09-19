import asyncio
import hashlib
import json
import time
from collections import OrderedDict
from dataclasses import dataclass
from math import asin, cos, isfinite, radians, sin, sqrt

import httpx


@dataclass(frozen=True)
class Coordinate:
    lat: float
    lon: float


@dataclass(frozen=True)
class RouteResult:
    provider: str
    coordinates: list[list[float]]
    distance_meters: int
    duration_seconds: int

    @property
    def geometry_hash(self) -> str:
        canonical = json.dumps(self.coordinates, separators=(",", ":"))
        return hashlib.sha256(canonical.encode()).hexdigest()


def haversine_meters(a: Coordinate, b: Coordinate) -> float:
    radius = 6_371_000.0
    dlat, dlon = radians(b.lat - a.lat), radians(b.lon - a.lon)
    value = sin(dlat / 2) ** 2 + cos(radians(a.lat)) * cos(radians(b.lat)) * sin(dlon / 2) ** 2
    return 2 * radius * asin(sqrt(value))


def geodesic_fallback(origin: Coordinate, destination: Coordinate, points: int = 24) -> RouteResult:
    coordinates = [
        [origin.lon + (destination.lon - origin.lon) * i / points,
         origin.lat + (destination.lat - origin.lat) * i / points]
        for i in range(points + 1)
    ]
    distance = round(haversine_meters(origin, destination) * 1.18)
    duration = max(60, round(distance / (42_000 / 3_600)))
    return RouteResult("geodesic-fallback", coordinates, distance, duration)


def parse_osrm(data: dict) -> RouteResult:
    if data.get("code") != "Ok" or not data.get("routes"):
        raise ValueError("OSRM returned no route")
    route = data["routes"][0]
    coordinates = route["geometry"]["coordinates"]
    if not isinstance(coordinates, list) or not 2 <= len(coordinates) <= 10_000:
        raise ValueError("OSRM returned invalid geometry")
    if any(not isinstance(point, list) or len(point) != 2 or
           any(isinstance(value, bool) or not isinstance(value, (int, float)) or not isfinite(value) for value in point) or
           not -180 <= point[0] <= 180 or not -90 <= point[1] <= 90 for point in coordinates):
        raise ValueError("OSRM returned invalid coordinates")
    distance, duration = route["distance"], route["duration"]
    if any(isinstance(value, bool) or not isinstance(value, (int, float)) or not isfinite(value) or value <= 0
           for value in (distance, duration)):
        raise ValueError("OSRM returned invalid distance or duration")
    return RouteResult("osrm", coordinates, round(distance), round(duration))


class RoutePlanner:
    def __init__(self, provider: str, osrm_base_url: str, timeout_seconds: float = 2.5,
                 cache_ttl_seconds: float = 300):
        self.provider = provider.lower()
        if self.provider not in {"osrm", "geodesic"}:
            raise ValueError("routing provider must be osrm or geodesic")
        self.osrm_base_url = osrm_base_url.rstrip("/")
        if not 0 < timeout_seconds <= 30:
            raise ValueError("routing timeout must be greater than 0 and at most 30 seconds")
        if not 0 <= cache_ttl_seconds <= 86_400:
            raise ValueError("routing cache TTL must be between 0 and 86400 seconds")
        self.timeout_seconds = timeout_seconds
        self.cache_ttl_seconds = cache_ttl_seconds
        self._cache: OrderedDict[tuple[float, float, float, float], tuple[float, RouteResult]] = OrderedDict()
        self._cache_lock = asyncio.Lock()
        self._inflight: dict[tuple[float, float, float, float], asyncio.Task[RouteResult]] = {}
        self._client: httpx.AsyncClient | None = None

    async def plan(self, origin: Coordinate, destination: Coordinate) -> RouteResult:
        key = (origin.lat, origin.lon, destination.lat, destination.lon)
        async with self._cache_lock:
            cached = self._cache.get(key)
            if cached and cached[0] > time.monotonic():
                self._cache.move_to_end(key)
                return cached[1]
            task = self._inflight.get(key)
            if task is None:
                task = asyncio.create_task(self._plan_uncached(origin, destination))
                self._inflight[key] = task
        try:
            result = await asyncio.shield(task)
        except BaseException:
            async with self._cache_lock:
                if task.done() and self._inflight.get(key) is task:
                    self._inflight.pop(key, None)
            raise
        async with self._cache_lock:
            if self._inflight.get(key) is task:
                self._inflight.pop(key, None)
            if self.cache_ttl_seconds > 0:
                self._cache[key] = (time.monotonic() + self.cache_ttl_seconds, result)
                self._cache.move_to_end(key)
                while len(self._cache) > 1024:
                    self._cache.popitem(last=False)
        return result

    async def _plan_uncached(self, origin: Coordinate, destination: Coordinate) -> RouteResult:
        if self.provider != "osrm":
            return geodesic_fallback(origin, destination)
        url = (f"{self.osrm_base_url}/route/v1/driving/"
               f"{origin.lon},{origin.lat};{destination.lon},{destination.lat}")
        try:
            if self._client is None:
                self._client = httpx.AsyncClient(timeout=self.timeout_seconds)
            response = await self._client.get(url, params={"overview": "full", "geometries": "geojson", "steps": "false"})
            response.raise_for_status()
            return parse_osrm(response.json())
        except (httpx.HTTPError, ValueError, KeyError, TypeError):
            return geodesic_fallback(origin, destination)

    async def close(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None

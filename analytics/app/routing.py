import asyncio
import hashlib
import json
import time
from dataclasses import dataclass
from math import asin, cos, radians, sin, sqrt

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
    if len(coordinates) < 2:
        raise ValueError("OSRM returned invalid geometry")
    return RouteResult("osrm", coordinates, round(route["distance"]), round(route["duration"]))


class RoutePlanner:
    def __init__(self, provider: str, osrm_base_url: str, timeout_seconds: float = 2.5,
                 cache_ttl_seconds: float = 300):
        self.provider = provider.lower()
        self.osrm_base_url = osrm_base_url.rstrip("/")
        self.timeout_seconds = timeout_seconds
        self.cache_ttl_seconds = cache_ttl_seconds
        self._cache: dict[tuple[float, float, float, float], tuple[float, RouteResult]] = {}
        self._cache_lock = asyncio.Lock()

    async def plan(self, origin: Coordinate, destination: Coordinate) -> RouteResult:
        key = (origin.lat, origin.lon, destination.lat, destination.lon)
        cached = self._cache.get(key)
        if cached and cached[0] > time.monotonic():
            return cached[1]
        async with self._cache_lock:
            cached = self._cache.get(key)
            if cached and cached[0] > time.monotonic():
                return cached[1]
            result = await self._plan_uncached(origin, destination)
            if len(self._cache) >= 1024:
                self._cache.clear()
            self._cache[key] = (time.monotonic() + self.cache_ttl_seconds, result)
            return result

    async def _plan_uncached(self, origin: Coordinate, destination: Coordinate) -> RouteResult:
        if self.provider != "osrm":
            return geodesic_fallback(origin, destination)
        url = (f"{self.osrm_base_url}/route/v1/driving/"
               f"{origin.lon},{origin.lat};{destination.lon},{destination.lat}")
        try:
            async with httpx.AsyncClient(timeout=self.timeout_seconds) as client:
                response = await client.get(url, params={"overview": "full", "geometries": "geojson", "steps": "false"})
                response.raise_for_status()
                return parse_osrm(response.json())
        except (httpx.HTTPError, ValueError, KeyError, TypeError):
            return geodesic_fallback(origin, destination)

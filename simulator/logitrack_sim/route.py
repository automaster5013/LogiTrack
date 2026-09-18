from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from math import asin, cos, radians, sin, sqrt


@dataclass(frozen=True)
class Point:
    lat: float
    lon: float


def interpolate(origin: Point, destination: Point, steps: int) -> list[Point]:
    """Deterministic straight-line route used until a road router is introduced."""
    if steps < 2:
        raise ValueError("steps must be at least 2")
    return [Point(origin.lat + (destination.lat-origin.lat)*i/steps,
                  origin.lon + (destination.lon-origin.lon)*i/steps)
            for i in range(1, steps+1)]


def distance_km(a: Point, b: Point) -> float:
    radius = 6371.0
    dlat, dlon = radians(b.lat-a.lat), radians(b.lon-a.lon)
    h = sin(dlat/2)**2 + cos(radians(a.lat))*cos(radians(b.lat))*sin(dlon/2)**2
    return 2*radius*asin(sqrt(h))


def eta(point: Point, destination: Point, speed_kph: float = 45.0) -> str:
    remaining_hours = distance_km(point, destination) / speed_kph
    return (datetime.now(timezone.utc) + timedelta(hours=remaining_hours)).isoformat().replace("+00:00", "Z")


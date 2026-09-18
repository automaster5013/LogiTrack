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


def sample_route(route: list[Point], steps: int) -> list[Point]:
    """Sample an arbitrary route at equal traveled-distance intervals."""
    if steps < 2:
        raise ValueError("steps must be at least 2")
    if len(route) < 2:
        raise ValueError("route must have at least two points")
    segments = [distance_km(route[i], route[i + 1]) for i in range(len(route) - 1)]
    total = sum(segments)
    if total == 0:
        return [route[-1]] * steps
    result: list[Point] = []
    segment_index, covered = 0, 0.0
    for step in range(1, steps + 1):
        target = total * step / steps
        while segment_index < len(segments) - 1 and covered + segments[segment_index] < target:
            covered += segments[segment_index]
            segment_index += 1
        length = segments[segment_index]
        ratio = 1.0 if length == 0 else (target - covered) / length
        start, end = route[segment_index], route[segment_index + 1]
        result.append(Point(start.lat + (end.lat - start.lat) * ratio,
                            start.lon + (end.lon - start.lon) * ratio))
    return result


def distance_km(a: Point, b: Point) -> float:
    radius = 6371.0
    dlat, dlon = radians(b.lat-a.lat), radians(b.lon-a.lon)
    h = sin(dlat/2)**2 + cos(radians(a.lat))*cos(radians(b.lat))*sin(dlon/2)**2
    return 2*radius*asin(sqrt(h))


def eta(point: Point, destination: Point, speed_kph: float = 45.0) -> str:
    remaining_hours = distance_km(point, destination) / speed_kph
    return (datetime.now(timezone.utc) + timedelta(hours=remaining_hours)).isoformat().replace("+00:00", "Z")


def planned_eta(duration_seconds: int, progress: float) -> str:
    remaining = max(0, round(duration_seconds * (1 - progress)))
    return (datetime.now(timezone.utc) + timedelta(seconds=remaining)).isoformat().replace("+00:00", "Z")

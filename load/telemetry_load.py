import json
import math
import statistics
import time
import uuid
from datetime import datetime, timedelta, timezone
from urllib.request import Request, urlopen

from confluent_kafka import Producer


API = "http://api:8080"
BROKER = "kafka:29092"


def request_json(url: str, method: str = "GET", body: dict | None = None, headers: dict | None = None):
    data = json.dumps(body).encode() if body is not None else None
    request = Request(url, data=data, method=method, headers={"Content-Type": "application/json", **(headers or {})})
    with urlopen(request, timeout=10) as response:
        return json.load(response)


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * fraction) - 1)]


def main() -> int:
    suffix = uuid.uuid4().hex[:8]
    delivery = request_json(f"{API}/api/deliveries", "POST", {
        "orderNumber": f"ORD-TELEMETRY-{suffix}", "vehicleId": f"TRUCK-TELEMETRY-{suffix}",
        "origin": {"name": "Seoul", "lat": 37.5665, "lon": 126.978},
        "destination": {"name": "Incheon", "lat": 37.4563, "lon": 126.7052},
    }, {"Idempotency-Key": f"telemetry-{suffix}"})
    producer = Producer({"bootstrap.servers": BROKER, "linger.ms": 5})
    latencies: list[float] = []
    total = 100

    for batch in range(10):
        target_progress = round((batch + 1) / 10 * 0.9, 4)
        started = time.perf_counter()
        for index in range(1, 11):
            sequence = batch * 10 + index
            progress = round(sequence / total * 0.9, 4)
            event = {
                "eventId": str(uuid.uuid4()), "eventType": "vehicle.telemetry.v1",
                "occurredAt": datetime.now(timezone.utc).isoformat(), "traceId": f"telemetry-{suffix}-{sequence}",
                "schemaVersion": 1, "payload": {
                    "deliveryId": delivery["id"], "lat": 37.5665 + (37.4563 - 37.5665) * progress,
                    "lon": 126.978 + (126.7052 - 126.978) * progress, "progress": progress,
                    "eta": (datetime.now(timezone.utc) + timedelta(minutes=30)).isoformat(), "status": "IN_TRANSIT",
                },
            }
            producer.produce("vehicle.telemetry.v1", key=delivery["id"], value=json.dumps(event, separators=(",", ":")))
        producer.flush(5)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            deliveries = request_json(f"{API}/api/deliveries")
            current = next(item for item in deliveries if item["id"] == delivery["id"])
            if current["progress"] >= target_progress:
                break
            time.sleep(0.05)
        else:
            raise RuntimeError(f"Telemetry batch {batch} was not reflected")
        latencies.append((time.perf_counter() - started) * 1000)

    elapsed = sum(latencies) / 1000
    summary = {
        "deliveryId": delivery["id"], "events": total,
        "throughputPerSecond": round(total / elapsed, 2),
        "batchLatencyMs": {"mean": round(statistics.fmean(latencies), 2), "p95": round(percentile(latencies, .95), 2), "max": round(max(latencies), 2)},
    }
    print(json.dumps(summary, indent=2))
    return 0 if summary["batchLatencyMs"]["p95"] <= 1000 else 1


if __name__ == "__main__":
    raise SystemExit(main())


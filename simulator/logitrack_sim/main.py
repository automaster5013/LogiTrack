import json
import os
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from threading import BoundedSemaphore
from urllib.request import urlopen

from confluent_kafka import Consumer, Producer
from .route import Point, eta, interpolate, planned_eta, sample_route


BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP", "localhost:9092")
API_URL = os.getenv("API_URL", "http://localhost:8080")
INTERVAL = float(os.getenv("SIMULATION_INTERVAL_SECONDS", "1"))
STEPS = int(os.getenv("SIMULATION_STEPS", "20"))
WORKERS = int(os.getenv("SIMULATION_MAX_WORKERS", "8"))
HEALTH_FILE = Path(os.getenv("SIMULATOR_HEALTH_FILE", "/tmp/logitrack-simulator-heartbeat"))


def validate_config(interval: float, steps: int, workers: int) -> None:
    if not 0.05 <= interval <= 60:
        raise ValueError("simulation interval must be between 0.05 and 60 seconds")
    if not 2 <= steps <= 1000:
        raise ValueError("simulation steps must be between 2 and 1000")
    if not 1 <= workers <= 100:
        raise ValueError("simulation workers must be between 1 and 100")
    if interval * steps > 120:
        raise ValueError("a simulation may run for at most 120 seconds")


validate_config(INTERVAL, STEPS, WORKERS)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def mark_healthy(path: Path = HEALTH_FILE) -> None:
    path.touch()


def pending_step_indexes(current_progress: float, steps: int) -> list[int]:
    return [index for index in range(1, steps + 1) if round(index / steps, 4) > current_progress]


def load_delivery_state(delivery_id: str, api_url: str = API_URL) -> tuple[float, str]:
    with urlopen(f"{api_url}/api/deliveries/{delivery_id}", timeout=5) as response:
        delivery = json.load(response)
    return float(delivery["progress"]), str(delivery["status"])


def simulate(producer: Producer, event: dict) -> None:
    payload = event["payload"]
    current_progress, current_status = load_delivery_state(payload["deliveryId"])
    if current_status == "DELIVERED":
        return
    origin, destination = Point(**payload["origin"]), Point(**payload["destination"])
    route = [Point(lat=coordinate[1], lon=coordinate[0]) for coordinate in payload.get("route", [])]
    points = sample_route(route, STEPS) if len(route) >= 2 else interpolate(origin, destination, STEPS)
    planned_duration = payload.get("plannedDurationSeconds")
    for index in pending_step_indexes(current_progress, STEPS):
        point = points[index - 1]
        progress = round(index / STEPS, 4)
        status = "DELIVERED" if index == STEPS else "IN_TRANSIT"
        telemetry = {
            "eventId": str(uuid.uuid4()), "eventType": "vehicle.telemetry.v1",
            "occurredAt": utc_now(), "traceId": event.get("traceId", str(uuid.uuid4())), "schemaVersion": 1,
            "payload": {"deliveryId": payload["deliveryId"], "vehicleId": payload["vehicleId"],
                        "lat": point.lat, "lon": point.lon, "progress": progress,
                        "status": status, "eta": None if status == "DELIVERED" else
                        (planned_eta(planned_duration, progress) if planned_duration else eta(point, destination))}
        }
        producer.produce("vehicle.telemetry.v1", key=payload["deliveryId"], value=json.dumps(telemetry))
        producer.flush(5)
        time.sleep(INTERVAL)


def main() -> None:
    consumer = Consumer({"bootstrap.servers": BOOTSTRAP, "group.id": "gps-simulator-v1", "auto.offset.reset": "earliest"})
    producer = Producer({"bootstrap.servers": BOOTSTRAP, "enable.idempotence": True})
    consumer.subscribe(["delivery.created.v1"])
    executor = ThreadPoolExecutor(max_workers=WORKERS, thread_name_prefix="delivery-sim")
    slots = BoundedSemaphore(WORKERS * 2)
    mark_healthy()

    def completed(future) -> None:
        slots.release()
        error = future.exception()
        if error is not None:
            print(f"Simulation rejected: {type(error).__name__}: {error}", flush=True)

    try:
        while True:
            message = consumer.poll(1.0)
            mark_healthy()
            if message is None: continue
            if message.error():
                print(f"Kafka error: {message.error()}", flush=True); continue
            try:
                event = json.loads(message.value())
            except (json.JSONDecodeError, TypeError) as error:
                print(f"Invalid delivery event ignored: {error}", flush=True)
                continue
            while not slots.acquire(timeout=1):
                mark_healthy()
            future = executor.submit(simulate, producer, event)
            future.add_done_callback(completed)
    finally:
        consumer.close()
        executor.shutdown(wait=True, cancel_futures=False)


if __name__ == "__main__":
    main()

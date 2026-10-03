import json
import math
import os
import re
import time
import uuid
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from queue import Empty, Queue
from threading import BoundedSemaphore, Event
from urllib.request import urlopen

from confluent_kafka import Consumer, Producer, TopicPartition
from .route import Point, eta, interpolate, planned_eta, sample_route


BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP", "localhost:9092")
API_URL = os.getenv("API_URL", "http://localhost:8080")
INTERVAL = float(os.getenv("SIMULATION_INTERVAL_SECONDS", "1"))
STEPS = int(os.getenv("SIMULATION_STEPS", "20"))
WORKERS = int(os.getenv("SIMULATION_MAX_WORKERS", "8"))
RESUME_FROM_API = os.getenv("SIMULATION_RESUME_FROM_API", "true").lower()
HEALTH_FILE = Path(os.getenv("SIMULATOR_HEALTH_FILE", "/tmp/logitrack-simulator-heartbeat"))
DELIVERY_TIMEOUT_SECONDS = 5
MAX_ROUTE_POINTS = 10_000
SAFE_TRACE = re.compile(r"[A-Za-z0-9._:-]{1,128}")


class InvalidDeliveryEvent(ValueError):
    """A permanent delivery event contract violation that is safe to skip."""


def _required_string(value: object, field: str, maximum: int) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > maximum:
        raise InvalidDeliveryEvent(f"{field} must be a non-blank string of at most {maximum} characters")
    return value


def _coordinate(value: object, field: str, minimum: float, maximum: float) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise InvalidDeliveryEvent(f"{field} must be a JSON number")
    coordinate = float(value)
    if not math.isfinite(coordinate) or not minimum <= coordinate <= maximum:
        raise InvalidDeliveryEvent(f"{field} must be finite and between {minimum} and {maximum}")
    return coordinate


def _point(value: object, field: str) -> dict[str, float]:
    if not isinstance(value, dict):
        raise InvalidDeliveryEvent(f"{field} must be an object")
    return {
        "lat": _coordinate(value.get("lat"), f"{field}.lat", -90, 90),
        "lon": _coordinate(value.get("lon"), f"{field}.lon", -180, 180),
    }


def decode_delivery_event(raw: bytes | str) -> dict:
    """Decode and normalize the permanent delivery.created.v1 input contract."""
    try:
        event = json.loads(raw)
    except (json.JSONDecodeError, UnicodeDecodeError, TypeError) as error:
        raise InvalidDeliveryEvent(f"invalid JSON: {error}") from error
    if not isinstance(event, dict):
        raise InvalidDeliveryEvent("event must be an object")
    if event.get("eventType") != "delivery.created.v1":
        raise InvalidDeliveryEvent("eventType must be delivery.created.v1")
    if event.get("schemaVersion") != 1 or isinstance(event.get("schemaVersion"), bool):
        raise InvalidDeliveryEvent("schemaVersion must be 1")
    try:
        event["eventId"] = str(uuid.UUID(_required_string(event.get("eventId"), "eventId", 36)))
    except ValueError as error:
        raise InvalidDeliveryEvent("eventId must be a UUID") from error
    trace_id = event.get("traceId")
    if trace_id is not None and (not isinstance(trace_id, str) or SAFE_TRACE.fullmatch(trace_id) is None):
        raise InvalidDeliveryEvent("traceId contains unsupported characters or length")

    payload = event.get("payload")
    if not isinstance(payload, dict):
        raise InvalidDeliveryEvent("payload must be an object")
    try:
        payload["deliveryId"] = str(uuid.UUID(_required_string(payload.get("deliveryId"), "payload.deliveryId", 36)))
    except ValueError as error:
        raise InvalidDeliveryEvent("payload.deliveryId must be a UUID") from error
    payload["vehicleId"] = _required_string(payload.get("vehicleId"), "payload.vehicleId", 80)
    payload["origin"] = _point(payload.get("origin"), "payload.origin")
    payload["destination"] = _point(payload.get("destination"), "payload.destination")

    route = payload.get("route", [])
    if not isinstance(route, list) or len(route) > MAX_ROUTE_POINTS:
        raise InvalidDeliveryEvent(f"payload.route must be an array of at most {MAX_ROUTE_POINTS} points")
    normalized_route = []
    for index, coordinate in enumerate(route):
        if not isinstance(coordinate, (list, tuple)) or len(coordinate) != 2:
            raise InvalidDeliveryEvent(f"payload.route[{index}] must be a [longitude, latitude] pair")
        normalized_route.append([
            _coordinate(coordinate[0], f"payload.route[{index}][0]", -180, 180),
            _coordinate(coordinate[1], f"payload.route[{index}][1]", -90, 90),
        ])
    payload["route"] = normalized_route

    planned_duration = payload.get("plannedDurationSeconds")
    if planned_duration is not None:
        if isinstance(planned_duration, bool) or not isinstance(planned_duration, (int, float)):
            raise InvalidDeliveryEvent("payload.plannedDurationSeconds must be a JSON number")
        if not math.isfinite(float(planned_duration)) or planned_duration <= 0:
            raise InvalidDeliveryEvent("payload.plannedDurationSeconds must be finite and positive")
    return event


def validate_config(interval: float, steps: int, workers: int) -> None:
    if not 0.05 <= interval <= 60:
        raise ValueError("simulation interval must be between 0.05 and 60 seconds")
    if not 2 <= steps <= 1000:
        raise ValueError("simulation steps must be between 2 and 1000")
    if not 1 <= workers <= 100:
        raise ValueError("simulation workers must be between 1 and 100")
    if interval * steps > 3600:
        raise ValueError("a simulation may run for at most 3600 seconds")
    if RESUME_FROM_API not in {"true", "false"}:
        raise ValueError("SIMULATION_RESUME_FROM_API must be true or false")


validate_config(INTERVAL, STEPS, WORKERS)


def consumer_config() -> dict[str, object]:
    # A full staging simulation lasts one hour. When every execution slot is
    # occupied, the consumer may wait for the first worker before polling
    # again, so keep the group membership beyond one complete simulation.
    simulation_millis = int(INTERVAL * STEPS * 1000)
    return {
        "bootstrap.servers": BOOTSTRAP,
        "group.id": "gps-simulator-v1",
        "auto.offset.reset": "earliest",
        "enable.auto.commit": False,
        "max.poll.interval.ms": max(300_000, simulation_millis + 300_000),
    }


class ContiguousOffsetTracker:
    """Advance a partition only after every preceding simulation succeeds."""

    def __init__(self) -> None:
        self._pending: dict[tuple[str, int], deque[int]] = {}
        self._completed: dict[tuple[str, int], set[int]] = {}
        self._last_seen: dict[tuple[str, int], int] = {}

    def register(self, topic: str, partition: int, offset: int) -> None:
        key = (topic, partition)
        if key not in self._pending:
            self._pending[key] = deque()
            self._completed[key] = set()
        if key in self._last_seen and offset <= self._last_seen[key]:
            raise ValueError("Kafka offsets must be registered once in delivery order")
        self._pending[key].append(offset)
        self._last_seen[key] = offset

    def complete(self, topic: str, partition: int, offset: int) -> TopicPartition | None:
        key = (topic, partition)
        if key not in self._pending or offset not in self._pending[key]:
            raise ValueError("Kafka offset completed without being registered")
        self._completed[key].add(offset)
        committed_offset = None
        while self._pending[key] and self._pending[key][0] in self._completed[key]:
            completed_offset = self._pending[key].popleft()
            self._completed[key].remove(completed_offset)
            committed_offset = completed_offset + 1
        return TopicPartition(topic, partition, committed_offset) if committed_offset is not None else None


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def mark_healthy(path: Path = HEALTH_FILE) -> None:
    path.touch()


def pending_step_indexes(current_progress: float, steps: int) -> list[int]:
    return [index for index in range(1, steps + 1) if round(index / steps, 4) > current_progress]


def telemetry_event_id(delivery_event_id: str, step_index: int) -> str:
    return str(uuid.uuid5(uuid.UUID(delivery_event_id), f"vehicle.telemetry.v1:{step_index}"))


def publish_telemetry(
    producer: Producer,
    delivery_id: str,
    telemetry: dict,
    timeout_seconds: float = DELIVERY_TIMEOUT_SECONDS,
) -> None:
    delivery_reports: list[object | None] = []
    report_received = Event()

    def delivered(error, _message) -> None:
        delivery_reports.append(error)
        report_received.set()

    producer.produce(
        "vehicle.telemetry.v1",
        key=delivery_id,
        value=json.dumps(telemetry),
        on_delivery=delivered,
    )
    deadline = time.monotonic() + timeout_seconds
    while not report_received.is_set():
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            producer.poll(0)
            if not report_received.is_set():
                raise RuntimeError("Kafka telemetry delivery report timed out")
            break
        producer.poll(min(0.1, remaining))
    if len(delivery_reports) != 1:
        raise RuntimeError("Kafka telemetry delivery report count was invalid")
    if delivery_reports[0] is not None:
        raise RuntimeError(f"Kafka telemetry delivery failed: {delivery_reports[0]}")


def load_delivery_state(delivery_id: str, api_url: str = API_URL) -> tuple[float, str]:
    with urlopen(f"{api_url}/api/deliveries/{delivery_id}", timeout=5) as response:
        delivery = json.load(response)
    return float(delivery["progress"]), str(delivery["status"])


def simulation_start_state(delivery_id: str) -> tuple[float, str]:
    if RESUME_FROM_API == "false":
        return 0.0, "CREATED"
    return load_delivery_state(delivery_id)


def simulate(producer: Producer, event: dict) -> None:
    payload = event["payload"]
    current_progress, current_status = simulation_start_state(payload["deliveryId"])
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
            "eventId": telemetry_event_id(event["eventId"], index), "eventType": "vehicle.telemetry.v1",
            "occurredAt": utc_now(), "traceId": event.get("traceId", str(uuid.uuid4())), "schemaVersion": 1,
            "payload": {"deliveryId": payload["deliveryId"], "vehicleId": payload["vehicleId"],
                        "lat": point.lat, "lon": point.lon, "progress": progress,
                        "status": status, "eta": None if status == "DELIVERED" else
                        (planned_eta(planned_duration, progress) if planned_duration else eta(point, destination))}
        }
        publish_telemetry(producer, payload["deliveryId"], telemetry)
        time.sleep(INTERVAL)


def main() -> None:
    consumer = Consumer(consumer_config())
    producer = Producer({
        "bootstrap.servers": BOOTSTRAP,
        "enable.idempotence": True,
        "delivery.timeout.ms": DELIVERY_TIMEOUT_SECONDS * 1000,
    })
    consumer.subscribe(["delivery.created.v1"])
    executor = ThreadPoolExecutor(max_workers=WORKERS, thread_name_prefix="delivery-sim")
    slots = BoundedSemaphore(WORKERS * 2)
    completions: Queue[tuple[object, BaseException | None]] = Queue()
    offsets = ContiguousOffsetTracker()
    mark_healthy()

    def completed(message, future) -> None:
        slots.release()
        completions.put((message, future.exception()))

    def commit_completed(message) -> None:
        next_offset = offsets.complete(message.topic(), message.partition(), message.offset())
        if next_offset is not None:
            consumer.commit(offsets=[next_offset], asynchronous=False)

    def drain_completions() -> None:
        while True:
            try:
                message, error = completions.get_nowait()
            except Empty:
                return
            if error is not None:
                raise RuntimeError(
                    f"Simulation failed before Kafka offset commit at "
                    f"{message.topic()}[{message.partition()}]@{message.offset()}"
                ) from error
            commit_completed(message)

    try:
        while True:
            drain_completions()
            message = consumer.poll(1.0)
            mark_healthy()
            if message is None:
                drain_completions()
                continue
            if message.error():
                print(f"Kafka error: {message.error()}", flush=True); continue
            offsets.register(message.topic(), message.partition(), message.offset())
            try:
                event = decode_delivery_event(message.value())
            except InvalidDeliveryEvent as error:
                print(f"Invalid delivery event ignored: {error}", flush=True)
                commit_completed(message)
                continue
            while not slots.acquire(timeout=1):
                mark_healthy()
                drain_completions()
            future = executor.submit(simulate, producer, event)
            future.add_done_callback(lambda result, consumed=message: completed(consumed, result))
    except Exception as error:
        # ThreadPoolExecutor waits for running workers during normal interpreter
        # shutdown. Exit immediately so Docker can restart and replay every
        # offset that was deliberately left uncommitted.
        print(f"Simulator stopping for durable Kafka replay: {error}", flush=True)
        os._exit(1)
    finally:
        consumer.close()
        executor.shutdown(wait=True, cancel_futures=False)


if __name__ == "__main__":
    main()

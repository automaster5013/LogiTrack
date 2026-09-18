import json
import os
import time
import uuid
from datetime import datetime, timezone
from threading import Thread

from confluent_kafka import Consumer, Producer
from .route import Point, eta, interpolate, planned_eta, sample_route


BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP", "localhost:9092")
INTERVAL = float(os.getenv("SIMULATION_INTERVAL_SECONDS", "1"))
STEPS = int(os.getenv("SIMULATION_STEPS", "20"))


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def simulate(producer: Producer, event: dict) -> None:
    payload = event["payload"]
    origin, destination = Point(**payload["origin"]), Point(**payload["destination"])
    route = [Point(lat=coordinate[1], lon=coordinate[0]) for coordinate in payload.get("route", [])]
    points = sample_route(route, STEPS) if len(route) >= 2 else interpolate(origin, destination, STEPS)
    planned_duration = payload.get("plannedDurationSeconds")
    for index, point in enumerate(points, start=1):
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
    try:
        while True:
            message = consumer.poll(1.0)
            if message is None: continue
            if message.error():
                print(f"Kafka error: {message.error()}", flush=True); continue
            event = json.loads(message.value())
            Thread(target=simulate, args=(producer, event), daemon=True).start()
    finally:
        consumer.close()


if __name__ == "__main__":
    main()

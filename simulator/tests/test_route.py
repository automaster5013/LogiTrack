import sys
import unittest
import uuid
import json
from unittest import mock
from pathlib import Path
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).parents[1]))
from logitrack_sim.route import Point, distance_km, interpolate, planned_eta, sample_route
from logitrack_sim import main
from logitrack_sim.main import ContiguousOffsetTracker, InvalidDeliveryEvent, consumer_config, decode_delivery_event, mark_healthy, pending_step_indexes, publish_telemetry, quarantine_invalid_delivery_event, simulation_start_state, telemetry_event_id, validate_config
from datetime import datetime, timezone


class RouteTest(unittest.TestCase):

    def delivery_event(self):
        return {
            "eventId": "8c9bf7fe-25f0-4d08-9a88-69dd4f1ad051",
            "eventType": "delivery.created.v1",
            "traceId": "trace.safe-1",
            "schemaVersion": 1,
            "payload": {
                "deliveryId": "7ae28b36-6178-42fa-a7ec-b4bed90867d1",
                "vehicleId": "truck-1",
                "origin": {"lat": 37.5, "lon": 126.9},
                "destination": {"lat": 37.4, "lon": 127.1},
                "route": [[126.9, 37.5], [127.1, 37.4]],
                "plannedDurationSeconds": 900,
            },
        }

    def test_decodes_and_normalizes_a_valid_delivery_event(self):
        event = decode_delivery_event(json.dumps(self.delivery_event()))

        self.assertEqual("truck-1", event["payload"]["vehicleId"])
        self.assertEqual([[126.9, 37.5], [127.1, 37.4]], event["payload"]["route"])

    def test_rejects_malformed_delivery_event_contracts(self):
        cases = [
            b"not-json",
            json.dumps([]),
            json.dumps({**self.delivery_event(), "eventType": "delivery.cancelled.v1"}),
            json.dumps({**self.delivery_event(), "schemaVersion": True}),
            json.dumps({**self.delivery_event(), "eventId": "not-a-uuid"}),
            json.dumps({**self.delivery_event(), "traceId": "unsafe trace"}),
        ]
        for payload_change in (
            {"deliveryId": "not-a-uuid"},
            {"vehicleId": " "},
            {"origin": {"lat": 91, "lon": 0}},
            {"destination": {"lat": 0, "lon": float("inf")}},
            {"route": [[126.9]]},
            {"plannedDurationSeconds": 0},
            {"plannedDurationSeconds": True},
        ):
            event = self.delivery_event()
            event["payload"].update(payload_change)
            cases.append(json.dumps(event))

        for raw in cases:
            with self.subTest(raw=raw), self.assertRaises(InvalidDeliveryEvent):
                decode_delivery_event(raw)

    def test_telemetry_publish_requires_a_successful_delivery_report(self):
        producer = mock.Mock()
        callback = {}
        producer.produce.side_effect = lambda _topic, **kwargs: callback.update(deliver=kwargs["on_delivery"])
        producer.poll.side_effect = lambda _timeout: callback["deliver"](None, object())

        publish_telemetry(producer, "delivery-1", {"eventId": "event-1"})

        producer.produce.assert_called_once()
        producer.poll.assert_called_once()

    def test_telemetry_publish_rejects_delivery_report_timeout(self):
        producer = mock.Mock()

        with self.assertRaisesRegex(RuntimeError, "timed out"):
            publish_telemetry(producer, "delivery-1", {"eventId": "event-1"}, timeout_seconds=0.001)

    def test_telemetry_publish_rejects_async_delivery_failure(self):
        producer = mock.Mock()
        producer.produce.side_effect = lambda _topic, **kwargs: kwargs["on_delivery"]("broker unavailable", object())
        producer.flush.return_value = 0

        with self.assertRaisesRegex(RuntimeError, "broker unavailable"):
            publish_telemetry(producer, "delivery-1", {"eventId": "event-1"})

    def test_telemetry_publish_rejects_duplicate_delivery_reports(self):
        producer = mock.Mock()
        producer.produce.side_effect = lambda _topic, **kwargs: (
            kwargs["on_delivery"](None, object()),
            kwargs["on_delivery"](None, object()),
        )

        with self.assertRaisesRegex(RuntimeError, "count was invalid"):
            publish_telemetry(producer, "delivery-1", {"eventId": "event-1"})

    def test_invalid_delivery_is_quarantined_verbatim_with_source_headers(self):
        producer = mock.Mock()
        producer.produce.side_effect = lambda _topic, **kwargs: kwargs["on_delivery"](None, object())
        message = mock.Mock()
        message.topic.return_value = "delivery.created.v1"
        message.partition.return_value = 2
        message.offset.return_value = 41
        message.key.return_value = b"delivery-key"
        message.value.return_value = b'{"payload":{"deliveryId":"bad"}}'

        quarantine_invalid_delivery_event(producer, message, InvalidDeliveryEvent("deliveryId must be a UUID"))

        topic, = producer.produce.call_args.args
        arguments = producer.produce.call_args.kwargs
        self.assertEqual("delivery.created.dlq.v1", topic)
        self.assertEqual(message.key(), arguments["key"])
        self.assertEqual(message.value(), arguments["value"])
        self.assertEqual([
            ("kafka_dlt-original-topic", "delivery.created.v1"),
            ("kafka_dlt-original-partition", "2"),
            ("kafka_dlt-original-offset", "41"),
            ("kafka_dlt-exception-message", "deliveryId must be a UUID"),
        ], arguments["headers"])

    def test_invalid_delivery_is_not_completed_when_quarantine_publish_fails(self):
        producer = mock.Mock()
        producer.produce.side_effect = lambda _topic, **kwargs: kwargs["on_delivery"]("broker unavailable", object())
        message = mock.Mock()
        message.topic.return_value = "delivery.created.v1"
        message.partition.return_value = 0
        message.offset.return_value = 7
        message.key.return_value = None
        message.value.return_value = b"not-json"

        with self.assertRaisesRegex(RuntimeError, "Kafka delivery quarantine delivery failed"):
            quarantine_invalid_delivery_event(producer, message, InvalidDeliveryEvent("invalid JSON"))

    def test_consumer_disables_automatic_commits_and_allows_a_full_simulation_between_polls(self):
        original_interval, original_steps = main.INTERVAL, main.STEPS
        try:
            main.INTERVAL, main.STEPS = 60, 60
            config = consumer_config()
            self.assertIs(False, config["enable.auto.commit"])
            self.assertEqual(3_900_000, config["max.poll.interval.ms"])
        finally:
            main.INTERVAL, main.STEPS = original_interval, original_steps

    def test_offsets_advance_only_across_contiguous_completed_simulations(self):
        tracker = ContiguousOffsetTracker()
        for offset in (10, 11, 14):
            tracker.register("delivery.created.v1", 2, offset)

        self.assertIsNone(tracker.complete("delivery.created.v1", 2, 11))
        committed = tracker.complete("delivery.created.v1", 2, 10)
        self.assertEqual(("delivery.created.v1", 2, 12), (committed.topic, committed.partition, committed.offset))
        committed = tracker.complete("delivery.created.v1", 2, 14)
        self.assertEqual(15, committed.offset)

    def test_offset_tracking_is_independent_per_partition(self):
        tracker = ContiguousOffsetTracker()
        tracker.register("delivery.created.v1", 0, 4)
        tracker.register("delivery.created.v1", 1, 9)
        self.assertEqual(10, tracker.complete("delivery.created.v1", 1, 9).offset)
        self.assertEqual(5, tracker.complete("delivery.created.v1", 0, 4).offset)

    def test_offset_tracker_rejects_duplicate_or_unknown_transitions(self):
        tracker = ContiguousOffsetTracker()
        tracker.register("delivery.created.v1", 0, 1)
        with self.assertRaises(ValueError):
            tracker.register("delivery.created.v1", 0, 1)
        with self.assertRaises(ValueError):
            tracker.complete("delivery.created.v1", 0, 2)

    def test_telemetry_event_ids_are_stable_per_delivery_event_step(self):
        delivery_event_id = "8c9bf7fe-25f0-4d08-9a88-69dd4f1ad051"
        first = telemetry_event_id(delivery_event_id, 1)
        self.assertEqual(first, telemetry_event_id(delivery_event_id, 1))
        self.assertNotEqual(first, telemetry_event_id(delivery_event_id, 2))
        self.assertEqual(5, uuid.UUID(first).version)

    def test_staging_can_start_new_delivery_without_authenticated_api_read(self):
        original = main.RESUME_FROM_API
        try:
            main.RESUME_FROM_API = "false"
            with mock.patch.object(main, "load_delivery_state") as loader:
                self.assertEqual((0.0, "CREATED"), simulation_start_state("delivery-1"))
                loader.assert_not_called()
        finally:
            main.RESUME_FROM_API = original
    def test_mark_healthy_creates_and_refreshes_heartbeat(self):
        with TemporaryDirectory() as directory:
            heartbeat = Path(directory) / "simulator-heartbeat"
            mark_healthy(heartbeat)
            first_modified = heartbeat.stat().st_mtime_ns
            mark_healthy(heartbeat)
            self.assertTrue(heartbeat.is_file())
            self.assertGreaterEqual(heartbeat.stat().st_mtime_ns, first_modified)

    def test_interpolation_reaches_destination(self):
        destination = Point(37.4563, 126.7052)
        route = interpolate(Point(37.5665, 126.9780), destination, 10)
        self.assertEqual(10, len(route))
        self.assertAlmostEqual(destination.lat, route[-1].lat)
        self.assertAlmostEqual(destination.lon, route[-1].lon)

    def test_distance_is_reasonable(self):
        km = distance_km(Point(37.5665, 126.9780), Point(37.4563, 126.7052))
        self.assertGreater(km, 20)
        self.assertLess(km, 40)

    def test_rejects_invalid_steps(self):
        with self.assertRaises(ValueError): interpolate(Point(0, 0), Point(1, 1), 1)

    def test_samples_polyline_by_traveled_distance(self):
        route = [Point(0, 0), Point(0, 2), Point(1, 2)]
        sampled = sample_route(route, 3)
        self.assertEqual(3, len(sampled))
        self.assertAlmostEqual(2, sampled[-1].lon)
        self.assertAlmostEqual(1, sampled[-1].lat)
        self.assertAlmostEqual(0, sampled[0].lat, places=2)

    def test_planned_eta_uses_remaining_route_duration(self):
        before = datetime.now(timezone.utc).timestamp()
        value = datetime.fromisoformat(planned_eta(1000, 0.25).replace("Z", "+00:00")).timestamp()
        self.assertGreaterEqual(value - before, 749)
        self.assertLessEqual(value - before, 751)

    def test_rejects_resource_exhausting_simulator_configuration(self):
        validate_config(60, 60, 15)
        for values in [(0, 20, 8), (1, 1, 8), (1, 20, 0), (60, 1000, 8)]:
            with self.assertRaises(ValueError): validate_config(*values)

    def test_resumes_after_the_last_applied_progress_step(self):
        self.assertEqual(list(range(1, 21)), pending_step_indexes(0, 20))
        self.assertEqual([19, 20], pending_step_indexes(0.9, 20))
        self.assertEqual([], pending_step_indexes(1, 20))


if __name__ == "__main__": unittest.main()

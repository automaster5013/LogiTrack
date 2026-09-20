import argparse
import http.client
import json
import math
import statistics
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.parse import SplitResult, urlsplit


connections = threading.local()


def get_connection(base_url: str) -> tuple[http.client.HTTPConnection, SplitResult]:
    target = urlsplit(base_url)
    connection_key = (target.scheme, target.hostname, target.port)
    connection = getattr(connections, "connection", None)
    if connection is None or getattr(connections, "key", None) != connection_key:
        connection_type = http.client.HTTPSConnection if target.scheme == "https" else http.client.HTTPConnection
        connection = connection_type(target.hostname, target.port, timeout=10)
        connections.connection = connection
        connections.key = connection_key
    return connection, target


def warm_connection(base_url: str, barrier: threading.Barrier) -> bool:
    barrier.wait()
    connection, _ = get_connection(base_url)
    connection.connect()
    return True


def post_delivery(base_url: str, key: str, order_number: str) -> tuple[float, int, str | None]:
    body = json.dumps({
        "orderNumber": order_number,
        "vehicleId": "TRUCK-LOAD",
        "origin": {"name": "Seoul", "lat": 37.5665, "lon": 126.978},
        "destination": {"name": "Incheon", "lat": 37.4563, "lon": 126.7052},
    })
    connection, target = get_connection(base_url)
    started = time.perf_counter()
    try:
        connection.request(
            "POST",
            f"{target.path.rstrip('/')}/api/deliveries",
            body=body,
            headers={"Content-Type": "application/json", "Idempotency-Key": key},
        )
        response = connection.getresponse()
        response.read()
        error = None if response.status == 201 else f"HTTP {response.status} {response.reason}"
        return (time.perf_counter() - started) * 1000, response.status, error
    except (OSError, TimeoutError, http.client.HTTPException) as error:
        connection.close()
        connections.connection = None
        return (time.perf_counter() - started) * 1000, 0, str(error)


def percentile(values: list[float], value: float) -> float:
    ordered = sorted(values)
    index = max(0, math.ceil(len(ordered) * value) - 1)
    return ordered[index]


def main() -> int:
    parser = argparse.ArgumentParser(description="LogiTrack delivery creation load test")
    parser.add_argument("--base-url", default="http://localhost:8080")
    parser.add_argument("--rate", type=int, default=20)
    parser.add_argument("--duration", type=int, default=15)
    parser.add_argument("--workers", type=int, default=32)
    parser.add_argument("--warmup", type=int, default=0, help="Untimed unique requests used to warm the JVM and pools")
    parser.add_argument("--unique", action="store_true", help="Create a new delivery for every request")
    parser.add_argument("--max-p95-ms", type=float, default=500)
    parser.add_argument("--min-success-percent", type=float, default=99)
    args = parser.parse_args()

    run_id = uuid.uuid4().hex[:10]
    stable_key = f"load-{run_id}"
    total = args.rate * args.duration
    results: list[tuple[float, int, str | None]] = []
    for index in range(args.warmup):
        warmup = post_delivery(args.base_url, f"warmup-{run_id}-{index}", f"LOAD-WARMUP-{run_id}-{index}")
        if warmup[1] != 201:
            print(json.dumps({"error": "unique warmup failed", "result": warmup}))
            return 1
    if not args.unique:
        warmup = post_delivery(args.base_url, stable_key, f"LOAD-{run_id}-0")
        if warmup[1] != 201:
            print(json.dumps({"error": "warmup failed", "result": warmup}))
            return 1
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        barrier = threading.Barrier(args.workers)
        connection_warmups = [pool.submit(warm_connection, args.base_url, barrier) for _ in range(args.workers)]
        if not all(future.result() for future in connection_warmups):
            print(json.dumps({"error": "worker connection warmup failed"}))
            return 1
        started = time.perf_counter()
        futures = []
        for index in range(total):
            target = started + index / args.rate
            remaining = target - time.perf_counter()
            if remaining > 0:
                time.sleep(remaining)
            key = f"load-{run_id}-{index}" if args.unique else stable_key
            futures.append(pool.submit(post_delivery, args.base_url, key, f"LOAD-{run_id}-{index if args.unique else 0}"))
        for future in as_completed(futures):
            results.append(future.result())

    elapsed = time.perf_counter() - started
    latencies = [latency for latency, _, _ in results]
    successes = [result for result in results if result[1] == 201]
    summary = {
        "scenario": "unique-create" if args.unique else "idempotent-create",
        "warmupRequests": args.warmup,
        "connectionWarmupWorkers": args.workers,
        "requests": len(results),
        "targetRps": args.rate,
        "achievedRps": round(len(results) / elapsed, 2),
        "successRatePercent": round(len(successes) / len(results) * 100, 2),
        "latencyMs": {
            "mean": round(statistics.fmean(latencies), 2),
            "p50": round(percentile(latencies, 0.50), 2),
            "p95": round(percentile(latencies, 0.95), 2),
            "p99": round(percentile(latencies, 0.99), 2),
            "max": round(max(latencies), 2),
        },
        "errors": [error for _, _, error in results if error][:5],
    }
    print(json.dumps(summary, indent=2))
    return 0 if (
        summary["successRatePercent"] >= args.min_success_percent
        and summary["latencyMs"]["p95"] <= args.max_p95_ms
    ) else 1


if __name__ == "__main__":
    raise SystemExit(main())

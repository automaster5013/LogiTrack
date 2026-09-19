import argparse
import json
import math
import statistics
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def post_delivery(base_url: str, key: str, order_number: str) -> tuple[float, int, str | None]:
    body = json.dumps({
        "orderNumber": order_number,
        "vehicleId": "TRUCK-LOAD",
        "origin": {"name": "Seoul", "lat": 37.5665, "lon": 126.978},
        "destination": {"name": "Incheon", "lat": 37.4563, "lon": 126.7052},
    }).encode()
    request = Request(
        f"{base_url}/api/deliveries",
        data=body,
        method="POST",
        headers={"Content-Type": "application/json", "Idempotency-Key": key},
    )
    started = time.perf_counter()
    try:
        with urlopen(request, timeout=10) as response:
            response.read()
            return (time.perf_counter() - started) * 1000, response.status, None
    except HTTPError as error:
        return (time.perf_counter() - started) * 1000, error.code, str(error)
    except (URLError, TimeoutError) as error:
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
    parser.add_argument("--unique", action="store_true", help="Create a new delivery for every request")
    args = parser.parse_args()

    run_id = uuid.uuid4().hex[:10]
    stable_key = f"load-{run_id}"
    total = args.rate * args.duration
    results: list[tuple[float, int, str | None]] = []
    if not args.unique:
        warmup = post_delivery(args.base_url, stable_key, f"LOAD-{run_id}-0")
        if warmup[1] != 201:
            print(json.dumps({"error": "warmup failed", "result": warmup}))
            return 1
    started = time.perf_counter()
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
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
    return 0 if summary["successRatePercent"] >= 99 and summary["latencyMs"]["p95"] <= 500 else 1


if __name__ == "__main__":
    raise SystemExit(main())

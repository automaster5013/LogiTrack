# 로컬 성능 기준선

측정일: 2026-09-19

## 배송 생성 API

로컬 Docker Compose 환경에서 멱등 재시도 workload를 초당 20건, 15초 동안 실행했다.

| 항목 | 결과 | 기준 |
|---|---:|---:|
| 요청 | 300 | 300 |
| 달성 처리량 | 20.04 RPS | 20 RPS |
| 성공률 | 100.0% | 99% 이상 |
| 평균 latency | 19.24 ms | 참고 |
| p95 latency | 35.63 ms | 500 ms 이하 |
| p99 latency | 41.76 ms | 참고 |
| 최대 latency | 48.17 ms | 참고 |

명령은 `./scripts/load-smoke.ps1`이다. 기본 시나리오는 같은 멱등 키의 재시도이므로 운영 클라이언트 retry 경로와 DB lookup 비용을 측정하며 테스트 데이터는 한 건만 생성한다. 모든 요청이 새 배송을 생성하는 write-heavy 시험은 `python ./load/delivery_load.py --rate 20 --duration 15 --unique`로 별도 실행할 수 있다.

도로 경로 분석은 동일 좌표를 5분간 최대 1,024건 캐시해 공개 OSRM 호출을 억제한다. 이는 외부 provider latency와 rate limit가 로컬 API 기준선을 왜곡하는 것을 줄이며, 서로 다른 좌표의 경로는 독립적으로 계산한다.

## 해석과 한계

- 이 결과는 단일 API 인스턴스의 로컬 기준선이며 운영 용량 보장을 의미하지 않는다.
- 고유 배송 생성 write-heavy workload는 격리된 테스트 DB에서 별도 측정한다.
- 측정 전후 컨테이너 health와 API 오류 로그를 확인한다.

## Telemetry 반영 지연

같은 `deliveryId` key로 10개씩 10 batch, 총 100개 Kafka telemetry를 persistent producer로 발행하고 각 batch의 최종 위치가 API에 반영될 때까지 측정했다. 시뮬레이터는 측정 중 자동 중지·복구한다.

| 항목 | 결과 | 기준 |
|---|---:|---:|
| 이벤트 | 100 | 100 |
| 처리량 | 36.64 events/s | 참고 |
| batch 평균 반영 | 272.93 ms | 참고 |
| batch p95 반영 | 307.95 ms | 1,000 ms 이하 |
| 종료 시 consumer lag | 0 | 0 |

명령은 `./scripts/telemetry-load.ps1`이다. 드라이버는 Compose 네트워크 내부에서 persistent Kafka producer를 사용하므로 매 batch의 CLI 프로세스 시작 시간은 측정값에 포함하지 않는다.

## 고유 배송 생성 격리 시험

기본 개발 데이터와 Kafka consumer offset에 영향을 주지 않도록 별도 Compose project, PostgreSQL volume, Redis, Kafka, analytics, API를 구성했다. deterministic geodesic routing과 20건 warm-up 후 모든 요청이 서로 다른 배송을 생성하는 write-heavy workload를 측정했다.

| 항목 | 결과 | 기준 |
|---|---:|---:|
| 측정 요청 | 150 | 150 |
| warm-up | 20 | 측정 제외 |
| 달성 처리량 | 10.05 RPS | 10 RPS |
| 성공률 | 100.0% | 99% 이상 |
| 평균 latency | 43.04 ms | 참고 |
| p95 latency | 62.80 ms | 500 ms 이하 |
| p99 latency | 72.99 ms | 참고 |

`./scripts/load-unique-isolated.ps1`은 `logitrack-perf` project를 시작하고 170개 row를 검증한 뒤 컨테이너·네트워크·전용 volume을 항상 제거한다. 기본 `logitrack` project와 데이터는 중단하거나 변경하지 않는다.

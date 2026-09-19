# 로컬 운영과 장애 처리

## Health와 관측성

- API liveness/readiness: `/actuator/health/liveness`, `/actuator/health/readiness`. Readiness는 애플리케이션 상태와 PostgreSQL을 포함하며 Redis는 로컬 SSE fallback이 있으므로 제외한다.
- analytics health: `http://localhost:8090/health`
- Prometheus scrape: `/actuator/prometheus`
- OpenTelemetry Collector health: `http://localhost:13133/`
- Tempo readiness: `http://localhost:3200/ready`
- 로그 필드: timestamp, level, logger, message, trace/correlation 식별자
- 주요 지표: API latency/error, Kafka consumer lag, telemetry 처리량, DLQ 수, 활성 SSE 연결

Grafana Explore에서 `Tempo` datasource를 선택해 service name 또는 trace ID로 조회한다. 로컬은 모든 trace를 sampling하며 운영 환경에서는 `TRACING_SAMPLING_PROBABILITY`를 트래픽과 비용에 맞게 조정한다. Collector 장애는 요청 처리를 막지 않으며 exporter가 bounded queue와 retry를 사용한다.

일별 KPI는 UTC 배송 생성일 cohort 기준으로 60초마다 갱신한다. `GET /api/reports/daily-kpis?days=14`는 JSON, `GET /api/reports/daily-kpis.csv?days=30`은 UTF-8 CSV, `GET /api/reports/daily-kpis.pdf?days=30`은 A4 가로형 운영 보고서를 반환하며 요청 범위는 1~90일로 제한한다. PDF는 API가 PostgreSQL projection을 조회한 뒤 analytics 서비스의 ReportLab 렌더러에 전달하므로 PDF만 실패할 때는 먼저 `http://localhost:8090/health`와 analytics 로그를 확인한다.

공개 route provider 보호와 반복 경로 응답 안정화를 위해 analytics는 동일 좌표 결과를 기본 300초 캐시한다. `ROUTING_CACHE_TTL_SECONDS`로 조정하며 최대 1,024개를 넘으면 캐시를 비운다.

## 주문 운영

- 생성: `POST /api/orders`와 필수 `Idempotency-Key`; 주문은 배송 없이 `READY`로 저장된다.
- 조회: `GET /api/orders`; 연결된 배송 ID, 차량, 배송 상태도 함께 반환한다.
- 배차: `POST /api/orders/{id}/dispatch`와 필수 `Idempotency-Key`, body `{"vehicleId":"TRUCK-01"}`. 같은 주문에는 배송을 한 건만 연결한다.
- lifecycle topic: `order.created.v1`, `order.dispatched.v1`, `order.fulfilled.v1`.
- 배송 완료 telemetry가 적용되는 동일 트랜잭션에서 연결 주문을 `FULFILLED`로 바꾸고 완료 outbox 이벤트를 기록한다. PostgreSQL이 주문/배송 상태의 source of truth다.
- 검증: `./scripts/order-smoke.ps1`는 simulator를 잠시 중단해 결정론적 완료 telemetry를 발행하고 종료 시 반드시 복구한다.

## 실패 시나리오

- simulator 중단: 배송 생성/조회는 유지되며 위치 갱신만 정지한다. 재시작 후 새 이벤트부터 처리한다.
- 외부 route provider 중단/지연: analytics가 제한 시간 뒤 geodesic fallback으로 전환하며 provider 필드에 fallback 사용을 기록한다.
- 경로 이탈/지연: 활성 경고는 배송·유형별 하나로 병합되고 정상 범위 복귀 시 `RESOLVED`로 남는다. 운영자는 콘솔의 `ACKNOWLEDGE` 또는 `POST /api/alerts/{id}/acknowledgement`와 `X-Operator` 헤더로 활성 경고를 확인한다. 최초 확인자와 시각은 변경 불가능한 감사 정보로 남고, 중복 요청은 추가 이벤트를 만들지 않는다. 상태 전이 이벤트는 outbox에서 `delivery.alert.v1`으로 발행된다.
- 경고 임계값: `GET /api/alert-policies`에서 전역(`*`)·차량별 정책을 조회하고 `POST /api/alert-policies`와 필수 `X-Operator`로 저장한다. `DELETE /api/alert-policies/{vehicleId}`는 차량 정책을 soft reset해 전역값 상속으로 되돌리며 전역 정책 삭제는 거부한다. 차량별 정책이 없으면 전역값을 사용하고 `CLOSE < OPEN ≤ CRITICAL` 순서를 API와 DB가 모두 검증한다. `GET /api/alert-policies/audits`는 `UPSERT`·`RESET`·`RESTORE` 최근 50개 불변 snapshot을 반환하며, `POST /api/alert-policies/audits/{auditId}/restore`와 필수 `X-Operator`로 선택한 snapshot을 다시 활성 정책으로 적용한다. 복원 작업도 별도의 `RESTORE` snapshot으로 감사된다. `./scripts/alert-policy-smoke.ps1`는 재정의의 경고 억제, reset 직후 전역 임계값 적용, 과거 snapshot 복원과 감사 3건을 검증한다.
- 잘못된 telemetry: 제한된 backoff 재시도 후 `vehicle.telemetry.dlq.v1`로 격리한다.
- Kafka 중단: DB 조회/생성은 유지하고 생성 이벤트는 outbox에 남는다. publisher가 최대 20회 재시도하며 이후 `FAILED` 상태는 관제 화면 또는 `POST /api/operations/outbox/failures/{id}/retry`와 `X-Operator`로 재처리한다. 최근 실패·재시도 감사는 각각 `/api/operations/outbox/failures`, `/api/operations/outbox/retry-audits`에서 조회한다.
- Redis 중단: DB가 source of truth이며 cache miss로 처리한다. SSE 다중 인스턴스 fan-out은 degraded 상태가 되지만 API readiness는 유지한다.
- DB 중단: API readiness가 실패하고 Kafka consumer가 재시도한다. broker의 이벤트는 보존된다.

전체 장애 주입 절차와 수동 복구 명령은 [장애 주입 및 복구 runbook](failure-recovery-runbook.md)에 있다. `./scripts/recovery-drill.ps1`는 analytics fallback, consumer 강제 종료 중 Kafka buffering, Redis degraded fan-out을 순서대로 검증하며 모든 중지 서비스를 `finally`에서 재시작한다.

Redis 장애가 Kafka consumer 트랜잭션을 오래 점유하지 않도록 연결과 명령 timeout은 기본 2초다. `REDIS_CONNECT_TIMEOUT`, `REDIS_COMMAND_TIMEOUT`으로 조정할 수 있으며, timeout 뒤에는 `reason="redis_error"` fallback 지표가 증가한다.

웹 콘솔은 `GET /api/runtime-version`을 15초마다 확인한다. 웹 컨테이너가 교체되어 runtime version이 바뀌면 열린 탭이 자동 새로고침되어 이전 정적 CSS/JavaScript를 계속 사용하는 상황을 방지한다. 탭이 백그라운드에 있다가 다시 보이면 즉시 한 번 확인한다. `./scripts/runtime-version-smoke.ps1`는 같은 runtime의 값이 안정적인지, 재시작 뒤 값이 바뀌는지 검증한다.

## SSE fan-out 운영

- Redis channel: `logitrack.stream.v1` (`STREAM_CHANNEL`로 변경 가능)
- 인스턴스 식별: `INSTANCE_ID`; SSE `connected` 이벤트에 포함
- 지표: `logitrack_sse_connections`, `logitrack_sse_redis_published_total`, `logitrack_sse_redis_received_total`, `logitrack_sse_fallback_total`
- Redis 장애 중에는 이벤트를 처리한 API의 로컬 구독자만 갱신된다. PostgreSQL 상태는 계속 최신이므로 클라이언트 재연결/조회로 복구하며, Redis가 돌아오면 listener container가 재구독한다.

## DLQ 재처리 정책

원본 payload, 오류 유형, 최초/최종 실패 시간, trace ID를 보존한다. 운영자가 원인을 수정하고 event ID를 새로 만들지 않은 채 replay하여 consumer 멱등성을 검증한다. 자동 무한 replay는 금지한다.

- 목록: `GET /api/operations/dlq?status=PENDING`
- 단일 replay: `POST /api/operations/dlq/{id}/replay`와 필수 `X-Operator` 헤더
- 감사: `GET /api/operations/replay-audits`
- 동일 catalog 항목은 한 번만 replay할 수 있다. 영구 오류가 다시 DLQ로 가면 새 항목으로 조사한다.

### 선택 범위 replay

1. `POST /api/operations/replay-plans`에 `{"eventIds":[...]}`와 `X-Operator`를 보내 dry-run plan을 만든다.
2. 응답의 대상과 10분 만료 시각을 검토한다.
3. `POST /api/operations/replay-plans/{id}/execute`에 같은 `X-Operator`와 `X-Replay-Approval: APPROVE`를 보낸다.

기본 최대 20건, 5 events/s이며 각각 `logitrack.replay.batch-max-size`, `logitrack.replay.batch-rate-per-second`로 조정한다. 중복 실행은 거절하고 이벤트별 감사 행을 유지한다.

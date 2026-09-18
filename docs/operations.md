# 로컬 운영과 장애 처리

## Health와 관측성

- API liveness/readiness: `/actuator/health/liveness`, `/actuator/health/readiness`
- analytics health: `http://localhost:8090/health`
- Prometheus scrape: `/actuator/prometheus`
- 로그 필드: timestamp, level, logger, message, trace/correlation 식별자
- 주요 지표: API latency/error, Kafka consumer lag, telemetry 처리량, DLQ 수, 활성 SSE 연결

## 실패 시나리오

- simulator 중단: 배송 생성/조회는 유지되며 위치 갱신만 정지한다. 재시작 후 새 이벤트부터 처리한다.
- 외부 route provider 중단/지연: analytics가 제한 시간 뒤 geodesic fallback으로 전환하며 provider 필드에 fallback 사용을 기록한다.
- 잘못된 telemetry: 제한된 backoff 재시도 후 `vehicle.telemetry.dlq.v1`로 격리한다.
- Kafka 중단: DB 조회/생성은 유지하고 생성 이벤트는 outbox에 남는다. publisher가 최대 20회 재시도하며 이후 `FAILED` 상태는 운영자가 원인 확인 후 재처리한다.
- Redis 중단: DB가 source of truth이며 cache miss로 처리한다. SSE 다중 인스턴스 fan-out은 degraded 상태가 된다.
- DB 중단: API readiness가 실패하고 Kafka consumer가 재시도한다. broker의 이벤트는 보존된다.

## DLQ 재처리 정책

원본 payload, 오류 유형, 최초/최종 실패 시간, trace ID를 보존한다. 운영자가 원인을 수정하고 event ID를 새로 만들지 않은 채 replay하여 consumer 멱등성을 검증한다. 자동 무한 replay는 금지한다.

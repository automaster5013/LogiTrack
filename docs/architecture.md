# 아키텍처

## 서비스 경계

- `control-api`: 배송 command/query, 상태 전이, telemetry 소비, SSE fan-out
- `simulator`: 배송 생성 이벤트를 받아 결정론적 위치/상태 이벤트 생성
- `web`: 관제 운영 콘솔. API와 SSE만 사용하고 브로커에는 접근하지 않음
- 향후 `warehouse-service`: 재고 ledger와 입·출고 workflow
- 향후 `analytics-service`: 경로/ETA, 지연/이탈, 일별 KPI projection

초기에는 과도한 분산을 피하기 위해 배송 도메인의 command/query/consumer를 하나의 배포 단위로 두되, Kafka 계약과 DB 소유권으로 경계를 명확히 한다.

## 이벤트 흐름

```text
Operator -> POST /deliveries -> PostgreSQL(delivery + outbox)
                                            |
                                  outbox publisher -> delivery.created.v1
                                            |
                                      Python simulator
                                            |
                                  vehicle.telemetry.v1
                                            |
Kafka -> control-api consumer -> PostgreSQL/Redis -> SSE -> Web console
                    failures -> retry topics -> telemetry.dlq.v1
```

Kafka key는 `deliveryId`이며 동일 배송의 순서를 보존한다. 모든 이벤트 envelope는 `eventId`, `eventType`, `occurredAt`, `traceId`, `schemaVersion`, `payload`를 가진다. consumer는 `eventId`를 처리 이력에 기록해 at-least-once 전달에서도 멱등하게 동작한다.

## 핵심 데이터 모델

### deliveries

`id UUID PK`, `order_number`, `vehicle_id`, `status`, `origin_*`, `destination_*`, `current_lat/lon`, `progress`, `eta`, `idempotency_key UNIQUE`, `version`, `created_at`, `updated_at`

### processed_events

`event_id UUID PK`, `consumer_name`, `processed_at`. 중복 이벤트의 side effect를 방지한다.

### outbox_events

`id UUID PK`는 event ID와 같고, aggregate/type/topic/key/payload를 배송과 같은 DB 트랜잭션에 기록한다. publisher는 `FOR UPDATE SKIP LOCKED`로 batch를 선점하여 다중 인스턴스 중복 경쟁을 막고, 성공 시 `PUBLISHED`, 반복 실패 시 `FAILED`로 전환한다.

### 향후 모델

- `orders`: 고객 주문 aggregate와 배송 참조
- `inventory_ledger`: SKU별 불변 수량 이동(+/-), warehouse, reason, correlation ID
- `warehouse_tasks`: receiving/picking/dispatch 상태 머신
- `route_snapshots`: polyline, 계획 거리/시간, 알고리즘 버전
- `delivery_alerts`: DELAY/ROUTE_DEVIATION, severity, observed/resolved timestamp

## 저장소 구조

```text
api/             Spring Boot 제어/API 서비스
simulator/       Python GPS/상태 이벤트 생성기
web/             Next.js 운영 콘솔
infra/           Prometheus/Grafana 설정
docs/            요구사항, ADR, 운영 문서
scripts/         재현 가능한 smoke test
```

## 확장/격리 전략

- API는 stateless하게 수평 확장하고 SSE는 Redis pub/sub 또는 전용 gateway로 분리한다.
- telemetry topic partition 수와 consumer replica 수를 함께 늘린다. key 기반 순서는 유지한다.
- simulator와 analytics 장애는 command API를 막지 않는다.
- DB pool, Kafka consumer, SSE subscriber에 각각 제한을 두어 연쇄 고갈을 막는다.
- 재시도는 지수 backoff와 최대 횟수를 사용하며 영구 오류는 DLQ로 보낸다.

# 아키텍처

## 서비스 경계

- `control-api`: 배송 command/query, 상태 전이, telemetry 소비, SSE fan-out
- `simulator`: 배송 생성 이벤트를 받아 결정론적 위치/상태 이벤트 생성
- `analytics`: OSRM 호환 provider와 로컬 fallback을 사용하는 경로/ETA 계산, 공급자 장애 격리
- `web`: 관제 운영 콘솔. API와 SSE만 사용하고 브로커에는 접근하지 않음
- `warehouse` 모듈: 비관적 잠금 기반 재고, 입고·피킹·출고 workflow와 불변 ledger. 초기에는 control-api에 모듈로 배치하고 부하/팀 경계가 필요할 때 별도 서비스로 추출
- 일별 KPI projection: PostgreSQL cohort 집계, JSON/CSV 보고서, TypeScript 성과 차트

초기에는 과도한 분산을 피하기 위해 배송 도메인의 command/query/consumer를 하나의 배포 단위로 두되, Kafka 계약과 DB 소유권으로 경계를 명확히 한다.

## 이벤트 흐름

```text
Operator -> POST /deliveries -> analytics(route + ETA)
                              -> PostgreSQL(delivery + route snapshot + outbox)
                                            |
                                  outbox publisher -> delivery.created.v1
                                            |
                                      Python simulator
                                            |
                                  vehicle.telemetry.v1
                                            |
Kafka -> control-api consumer -> PostgreSQL -> Redis Pub/Sub -> every API SSE -> Web console
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

### route_snapshots

`delivery_id`, GeoJSON `geometry`, `provider`, `algorithm_version`, `geometry_hash`, `distance_meters`, `duration_seconds`, `planned_eta`, `generated_at`을 저장한다. 재계산 시 기존 스냅샷을 덮어쓰지 않아 계획 이력을 보존한다.

### delivery_alerts

배송별 `DELAY`, `ROUTE_DEVIATION` 경고의 심각도와 lifecycle을 저장한다. 활성 경고는 배송·유형별 하나만 허용하고 반복 관측은 `occurrence_count`와 최종 관측 시각을 갱신한다. 경로 이탈은 500m 발생/300m 해결, 지연은 계획 ETA 대비 10분 발생/5분 해결의 히스테리시스를 사용한다. 발생·심각도 상승·해결은 `delivery.alert.v1` outbox 이벤트로 발행한다.

### 향후 모델

- `orders`: 고객 주문 aggregate와 배송 참조
- `inventory_ledger`: SKU별 불변 수량 이동(+/-), warehouse, reason, correlation ID
- `warehouse_tasks`: receiving/picking/dispatch 상태 머신
- 향후 alert 정책: 차량·화물별 threshold, 운영자 확인(acknowledgement), notification routing

## 저장소 구조

```text
api/             Spring Boot 제어/API 서비스
simulator/       Python GPS/상태 이벤트 생성기
analytics/       Python 경로/ETA 분석 서비스
web/             Next.js 운영 콘솔
infra/           Prometheus, OpenTelemetry Collector, Tempo, Grafana 설정
docs/            요구사항, ADR, 운영 문서
scripts/         재현 가능한 smoke test
```

## 관측 경로

Spring API와 Python analytics는 OTLP/HTTP로 OpenTelemetry Collector에 span을 보낸다. Collector는 batch와 memory limiter를 거쳐 Tempo에 OTLP/gRPC로 전달하고 Grafana Explore가 Tempo를 조회한다. HTTP `traceparent`는 API에서 RestClient를 통해 analytics와 OSRM 호출까지 전파된다.

## 확장/격리 전략

- API 인스턴스는 로컬 SSE 연결만 보유한다. 배송·경고 갱신은 `logitrack.stream.v1` Redis Pub/Sub 채널로 모든 인스턴스에 fan-out하며, Redis publish 실패 시 발행 인스턴스의 로컬 연결에는 계속 전달한다.
- Compose `scale-test` profile은 8081의 두 번째 API를 제공해 교차 인스턴스 전달을 검증한다. 더 큰 규모에서는 동일 계약을 전용 realtime gateway로 옮길 수 있다.
- telemetry topic partition 수와 consumer replica 수를 함께 늘린다. key 기반 순서는 유지한다.
- simulator와 analytics 장애는 command API를 막지 않는다.
- DB pool, Kafka consumer, SSE subscriber에 각각 제한을 두어 연쇄 고갈을 막는다.
- 재시도는 지수 backoff와 최대 횟수를 사용하며 영구 오류는 DLQ로 보낸다.
- DLQ catalog consumer는 실패 payload/예외/offset을 PostgreSQL에 보존하고 운영 API가 원본 topic으로 단일 replay하며 감사 행을 기록한다.

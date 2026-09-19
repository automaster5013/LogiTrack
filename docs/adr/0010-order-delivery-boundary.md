# ADR 0010: 주문과 배송 aggregate 분리

## 상태

채택 - 2026-09-19

## 맥락

주문은 고객의 운송 요구이고 배송은 차량에 배차된 실행 단위다. 두 개념을 하나의 레코드로 취급하면 접수됐지만 아직 배차되지 않은 주문을 표현할 수 없고, 배차 멱등성이나 주문 이력도 배송 상태에 종속된다. 기존 직접 배송 API와 누적 데이터는 계속 동작해야 한다.

## 결정

- PostgreSQL `orders` 테이블과 `CustomerOrder` aggregate를 추가하고 `READY`, `DISPATCHED`, `FULFILLED` 상태를 관리한다.
- `deliveries.order_id`는 nullable FK와 부분 unique index를 사용한다. 신규 주문 흐름은 주문 하나에 배송 하나만 연결하고, 기존 직접 생성 배송은 `NULL`로 유지한다.
- 주문 생성과 배차는 각각 `Idempotency-Key`를 요구한다. 배차는 주문 비관적 잠금 안에서 배송·경로 스냅샷·상태·outbox를 원자적으로 기록한다.
- 주문 이벤트는 `order.created.v1`, `order.dispatched.v1`, `order.fulfilled.v1`으로 분리하고 주문 ID를 Kafka key로 사용한다.
- 배송 완료 telemetry 트랜잭션이 연결 주문을 완료시키므로 두 상태가 엇갈린 채 커밋되지 않는다.

## 결과

배차 전 주문을 독립적으로 조회하고 운영 콘솔에서 차량을 지정할 수 있다. PostgreSQL이 주문과 배송 관계의 source of truth이며 DB 제약과 잠금이 중복 배차를 방지한다. nullable 연결과 기존 API 유지로 이전 통합은 깨지지 않지만, 레거시 직접 배송에는 대응 주문이 자동 생성되지 않는다.

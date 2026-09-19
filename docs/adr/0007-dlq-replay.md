# ADR 0007: DLQ catalog와 선택 replay 감사

## 상태

채택됨 — 2026-09-19

## 결정

- `vehicle.telemetry.dlq.v1` 전용 catalog consumer가 실패 레코드와 Spring Kafka 예외 헤더를 PostgreSQL에 저장한다.
- `(dlq_topic, dlq_partition, dlq_offset)`를 유일 키로 사용해 catalog 재수신을 멱등 처리한다.
- 운영자는 단일 `PENDING` 이벤트만 원본 topic으로 replay할 수 있다. 같은 catalog 항목의 중복 replay는 HTTP 409로 거절한다.
- replay는 원본 payload와 event ID를 그대로 보존하며 `X-Operator`, 시각, 이벤트 ID를 별도 불변 감사 행으로 저장한다.
- 영구 poison event가 다시 실패하면 새 DLQ offset의 새 항목으로 격리되며 자동 반복 replay하지 않는다.

## 이유

Kafka의 DLQ만으로는 운영 콘솔에서 검색·선택·감사를 제공하기 어렵다. PostgreSQL catalog는 payload를 고치지 않고도 transient 장애를 안전하게 재시도하고, 모든 수동 조치를 추적할 수 있게 한다.

## 한계

현재 UI는 단일 이벤트 replay만 지원한다. 범위 replay는 rate limit, 승인, dry-run을 함께 설계한 뒤 추가한다.


# ADR-0001: 핵심 기술 스택

상태: Accepted — 2026-09-19

## 결정

- Java 21 + Spring Boot 3: 제어 API와 도메인 workflow
- Python 3.12: 시뮬레이터 및 향후 경로/ETA 분석
- Next.js + TypeScript: 운영 콘솔
- PostgreSQL: 주문/배송/재고의 transactional source of truth
- Redis: 최신 상태 cache와 향후 다중 인스턴스 SSE fan-out
- Kafka (KRaft): 재생 가능한 telemetry/event log
- Micrometer/Prometheus/Grafana, OpenTelemetry 확장 지점

## 비교와 이유

Kafka는 RabbitMQ보다 운영 요소가 많지만 이벤트 replay, consumer group, key ordering, partition 확장을 포트폴리오에서 구체적으로 증명할 수 있다. PostgreSQL과 MySQL 모두 이 프로젝트에 충분하며 두 제품 모두 JSON과 `SKIP LOCKED`를 지원한다. PostgreSQL은 향후 PostGIS 기반 경로·지오펜스 질의, 부분 인덱스 기반 outbox polling, 분석 SQL 및 확장 생태계를 하나의 운영 모델로 가져가기 좋아 선택했다. SSE는 브라우저 단방향 관제에 WebSocket보다 단순하고 자동 재연결이 있으므로 MVP에 선택하며, 양방향 명령이 필요할 때 WebSocket을 추가한다.

Spring Boot는 Python 단일 스택보다 초기 비용이 있지만 강한 도메인 모델, transaction, Kafka retry/DLQ, actuator를 일관되게 보여준다. 분석·시뮬레이션은 반복 속도와 과학 계산 생태계 때문에 Python으로 분리한다.

## 트레이드오프

로컬 메모리 사용량과 서비스 수가 증가한다. 개발 profile에서는 단일 Kafka broker와 단일 DB를 사용하고, production topology는 문서/부하 시험에서 검증한다. 배송 생성 이벤트는 PostgreSQL transactional outbox에 같은 트랜잭션으로 기록하고 별도 publisher가 Kafka로 전달한다. at-least-once 발행 가능성은 event ID 기반 consumer 멱등성으로 흡수한다.

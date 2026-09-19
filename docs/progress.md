# 구현 진행 현황

기준일: 2026-09-19

## 완료

- 프로젝트 요구사항, 성공 기준, 9주 로드맵과 기술 ADR
- Docker Compose 기반 PostgreSQL, Redis, Kafka, API, simulator, web, Prometheus, Grafana
- 멱등 배송 생성과 transactional outbox
- Python GPS/ETA simulator와 Kafka telemetry 처리
- SSE 실시간 배송 관제와 MapLibre 벡터 지도
- Kafka retry/DLQ 토픽과 명시적 topic initialization
- 창고 입고, 피킹 예약, 출고 확정 상태 전이
- 비관적 잠금과 DB 제약조건을 적용한 재고 정합성
- 불변 inventory ledger와 창고 outbox 이벤트
- TypeScript 창고 재고·ledger 운영 패널
- provider 교체형 도로 경로/ETA 분석 서비스와 장애 fallback
- PostgreSQL 불변 route snapshot, 경로 기반 차량 시뮬레이션과 고해상도 지도 geometry
- 지연·경로 이탈 탐지, 히스테리시스와 경고 발생·상향·해결 lifecycle
- 경고 outbox 이벤트와 TypeScript 실시간 exception management 패널
- Redis Pub/Sub 기반 다중 API SSE fan-out, 인스턴스 식별과 degraded local fallback
- 실제 두 API 인스턴스 교차 전달 smoke test와 SSE/Redis Micrometer 지표
- OpenTelemetry Collector와 Tempo, Grafana datasource 자동 프로비저닝
- Spring API→Python analytics→route provider W3C trace 전파와 재현 가능한 Tempo 검증

## 다음 우선순위

1. 일별 배송 KPI projection과 보고서

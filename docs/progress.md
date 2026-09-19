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
- PostgreSQL 일별 배송 KPI projection, JSON/CSV 보고서와 TypeScript 14일 성과 차트
- 동일 경로 TTL 캐시와 20 RPS 멱등 생성 API 부하 기준선(p95 35.63ms, 성공률 100%)
- DLQ PostgreSQL catalog, 단일 replay API, 운영자 감사 이력과 TypeScript 복구 패널
- Kafka telemetry 100건 batch 반영 p95 307.95ms, 처리량 36.64 events/s, 종료 lag 0 기준선
- 10분 데모 순서와 전체 재현 명령 문서
- 별도 Compose/PostgreSQL/Kafka 격리 환경의 고유 배송 생성 100 RPS 최종 기준선(p95 87.72ms, 성공률 100%)
- 최대 20건 DLQ replay dry-run plan, 10분 승인 창, 운영자 일치와 5 events/s 속도 제한
- PostgreSQL KPI 원본 기반 2페이지 운영 PDF, API/TypeScript 다운로드와 렌더링 품질 검증
- analytics/consumer/Redis 장애 주입, Kafka 보존·정확히 한 번 복구와 자동 원상 복구 runbook
- PostgreSQL 독립 주문 aggregate, 주문-배송 1:1 연결, `READY → DISPATCHED → FULFILLED` lifecycle과 TypeScript 배차 패널
- 배포 runtime version 감지와 자동 새로고침으로 오래 열린 운영 탭의 구형 CSS/JavaScript 및 검은 지도 상태 자동 복구
- JaCoCo 핵심 도메인 line/branch 80% 빌드 gate와 재현 가능한 Docker 검증(line 90.38%, branch 96.88%)

## 현재 상태

모든 예정 우선순위 완료. 이후 작업은 새 요구사항 또는 운영 검증 결과에 따라 결정한다.

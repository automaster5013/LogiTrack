# 요구사항과 성공 기준

## 제품 목표

LogiTrack은 GPS 장비가 없는 포트폴리오 환경에서 주문부터 배송 완료까지의 운영 흐름, 실시간 관제, 이벤트 장애 복구를 재현한다. 데모는 한 명이 10분 안에 실행하고 설명할 수 있어야 한다.

## 사용자와 핵심 시나리오

- 배차 운영자: 주문/배송 생성, 차량 현재 위치 및 ETA 확인, 지연·경로 이탈 알림 확인
- 창고 담당자: 입고, 피킹, 출고 이벤트 처리 및 재고 이동 이력 확인
- 운영 엔지니어: 처리량, 지연, 오류율, consumer lag, DLQ 확인 및 메시지 재처리
- 면접 평가자: 로컬에서 시스템 실행, 장애 주입, 추적 ID를 통한 흐름 확인

## 기능 요구사항

### MVP (1~5주)

- 멱등 키를 사용한 배송 생성과 상태 조회
- 차량/출발지/도착지 및 기본 직선 경로 저장
- Python 시뮬레이터의 위치·배송 이벤트 생성
- Kafka 이벤트 소비와 최신 위치 반영
- SSE 기반 배송 상태/위치 스트리밍
- 배송 목록과 실시간 이벤트 운영 콘솔
- Prometheus 메트릭, 구조화 로그, trace ID 전달
- 소비 실패 retry 및 DLQ 토픽
- Docker Compose 한 명령 실행, 자동 smoke test

### 후속 범위 (6~10주)

- 주문과 배송 분리, 창고 입고/피킹/출고 및 재고 ledger
- 도로망 기반 경로와 ETA, 지연·경로 이탈 탐지
- WebSocket 선택형 양방향 관제와 지도 UI
- transactional outbox/CDC, replay 관리 UI, DLQ 재처리 API
- 일별 배송 KPI 보고서와 CSV/PDF 내보내기
- OpenTelemetry Collector/Tempo를 통한 분산 추적
- 부하 시험, consumer autoscaling 설계, 장애 주입 및 복구 runbook
- 최소 비용 클라우드 최종 검증(별도 승인 시에만)

## 비기능 요구사항과 측정 가능한 성공 기준

| 항목 | MVP 기준 | 최종 기준 |
|---|---:|---:|
| 생성 API | p95 500ms 이하(로컬 20 RPS) | p95 300ms 이하(100 RPS) |
| 위치 반영 지연 | p95 2초 이하 | p95 1초 이하 |
| 가용성 격리 | simulator 중단 시 API 조회/생성 유지 | 단일 consumer 장애 시 자동 복구 |
| 정합성 | 동일 멱등 키의 중복 배송 0건 | outbox로 DB/event 원자성 보장 |
| 복구 | poison event가 DLQ로 이동 | 선택 구간 replay와 감사 이력 |
| 관측성 | health/metrics/구조화 로그 | 단일 trace로 API→Kafka→consumer 추적 |
| 실행성 | `docker compose up --build` | 새 환경 10분 이내 재현 |
| 품질 | 핵심 단위/통합 smoke test | 도메인 80%+ coverage, 부하/복구 시험 |

## 범위 밖

실제 운송사/GPS 연동, 결제, 운임 정산, 모바일 드라이버 앱, 실제 고객 개인정보, 기존 ReleasePilot AWS 자원의 사용 또는 변경은 포함하지 않는다.


# LogiTrack

[![CI](https://github.com/automaster5013/LogiTrack/actions/workflows/ci.yml/badge.svg)](https://github.com/automaster5013/LogiTrack/actions/workflows/ci.yml)

실제 GPS 장비 없이 배송 차량, 창고, 주문의 상태 변화를 재현하는 이벤트 기반 물류 운영 플랫폼입니다.

## 주문부터 배송 완료까지

1. API나 TypeScript 운영 콘솔에서 고객 주문을 `READY` 상태로 생성합니다.
2. 배차 시 독립된 배송 aggregate를 주문에 연결하고 `order.dispatched.v1`과 `delivery.created.v1`을 transactional outbox로 발행합니다.
3. Python 경로 분석 서비스가 도로망 경로와 ETA 스냅샷을 만들고, 시뮬레이터가 경로상의 GPS 점을 `vehicle.telemetry.v1`로 발행합니다.
4. Spring Boot가 최신 위치와 배송 상태를 저장하고 SSE로 브라우저에 전송합니다. 배송 완료 시 연결 주문도 `FULFILLED`로 전환합니다.
5. Next.js 콘솔에서 주문, 배송, 경로, 경고와 KPI를 함께 확인합니다.

## 빠른 시작

요구 사항: Docker Desktop + Docker Compose v2

```bash
docker compose up --build
```

- 운영 콘솔: http://localhost:3000
- API health: http://localhost:8080/actuator/health
- 경로 분석 health: http://localhost:8090/health
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3001 (`admin` / `admin`)
- Tempo API: http://localhost:3200 (`Grafana → Explore → Tempo`에서 trace 조회)
- OpenTelemetry Collector health: http://localhost:13133

샘플 주문 생성과 배차:

```bash
curl -X POST http://localhost:8080/api/orders \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: demo-001" \
  -d '{"orderNumber":"ORD-1001","origin":{"name":"Seoul Hub","lat":37.5665,"lon":126.9780},"destination":{"name":"Incheon DC","lat":37.4563,"lon":126.7052}}'

curl -X POST http://localhost:8080/api/orders/{orderId}/dispatch \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: dispatch-001" \
  -d '{"vehicleId":"TRUCK-01"}'
```

주문 조회: `GET /api/orders`, 배송 조회: `GET /api/deliveries`, 실시간 스트림: `GET /api/stream/deliveries`. 기존 `POST /api/deliveries`는 호환성을 위해 유지하지만 신규 운영 흐름은 주문 생성 후 배차를 사용합니다.

경로 스냅샷 조회는 `GET /api/routes`입니다. 개발 환경은 OSRM 호환 endpoint를 사용하며 2.5초 안에 응답하지 않거나 오류가 발생하면 로컬 geodesic 계산으로 자동 전환합니다. 공개 demo는 개발용이므로 운영에서는 `.env`의 `OSRM_BASE_URL`을 자체 호스팅 또는 계약된 공급자로 교체하세요. 완전한 오프라인 실행은 `ROUTING_PROVIDER=geodesic`으로 설정합니다.

운영 콘솔은 MapLibre 기반 벡터 지도에서 계획 경로, PostgreSQL에 저장된 실제 GPS 주행 궤적, 차량 상태와 ETA를 실시간으로 표시합니다. 지도와 telemetry 목록은 운행 중 차량만 표시하는 통합 `LIVE` 범위를 기본으로 사용해 누적 이력의 중첩을 피하고, `ALL`로 완료 배송까지 전환할 수 있습니다. 지도 헤더의 즉시 검색으로 차량·주문·출발지·도착지를 좁히면 지도와 목록이 동시에 반영되고, 검색 결과가 없을 때 복구 방법을 지도 위에 안내하며 선택 차량은 밝은 halo로 강조합니다. 기본 OpenFreeMap 스타일은 별도 API key 없이 동작하며, 운영용 지도 공급자는 `.env`의 `NEXT_PUBLIC_MAP_STYLE_URL`로 교체할 수 있습니다.

## 문서

- [요구사항과 성공 기준](docs/requirements.md)
- [8~10주 로드맵](docs/roadmap.md)
- [아키텍처 및 데이터 모델](docs/architecture.md)
- [기술 선택 ADR](docs/adr/0001-technology-stack.md)
- [실시간 지도 ADR](docs/adr/0002-live-map.md)
- [경로 분석 ADR](docs/adr/0003-route-analytics.md)
- [배송 경고 lifecycle ADR](docs/adr/0004-alert-lifecycle.md)
- [분산 추적 ADR](docs/adr/0005-distributed-tracing.md)
- [일별 KPI projection ADR](docs/adr/0006-daily-kpi-projection.md)
- [DLQ replay와 감사 ADR](docs/adr/0007-dlq-replay.md)
- [선택 범위 replay 승인 ADR](docs/adr/0008-batch-replay-approval.md)
- [KPI PDF 보고서 ADR](docs/adr/0009-kpi-pdf-reporting.md)
- [주문·배송 aggregate 분리 ADR](docs/adr/0010-order-delivery-boundary.md)
- [운영 및 장애 처리](docs/operations.md)
- [장애 주입 및 복구 runbook](docs/failure-recovery-runbook.md)
- [로컬 성능 기준선](docs/performance.md)
- [테스트 품질 기준선](docs/quality.md)
- [CI/CD와 릴리스 전략](docs/delivery.md)
- [10분 데모 시나리오](docs/demo.md)
- [구현 진행 현황](docs/progress.md)

## 로컬 검증

```bash
python -m unittest discover simulator/tests
docker compose config
python -m unittest discover analytics/tests
```

통합 smoke test는 전체 스택 실행 후 `./scripts/smoke.ps1`로 수행합니다.

핵심 도메인의 line/branch coverage 80% gate는 `./scripts/domain-coverage.ps1`로 실행합니다. 현재 기준선은 line 92.37%, branch 88.71%이며 기준 미달 시 빌드가 실패합니다.

GitHub Actions의 `CI` workflow는 main push와 pull request마다 API 테스트·coverage gate, Python analytics/simulator 테스트, Docker Compose 구성 검증, TypeScript production build를 병렬 실행합니다. workflow 권한은 저장소 읽기로 제한됩니다.

배포 가능한 production image와 non-root runtime은 `./scripts/container-build.ps1`로 검증합니다. 실제 CD는 배포 대상·비용 상한·비밀정보·rollback 정책 승인 후 스테이징부터 연결합니다.

차량별 경고 정책은 관제 화면의 `Vehicle threshold policies`에서 설정합니다. `GLOBAL DEFAULT`를 기준으로 차량별 경로 이탈(m)과 ETA 지연(s)의 `CLOSE < OPEN ≤ CRITICAL` 값을 재정의하며, `RESET TO GLOBAL`로 안전하게 상속 상태로 되돌릴 수 있습니다. 저장과 reset은 PostgreSQL 불변 감사 이력에 운영자와 함께 남고, 각 감사 snapshot의 `RESTORE`로 과거 임계값을 다시 적용할 수 있습니다. 복원 자체도 `RESTORE` 감사 기록을 생성합니다. 종단 간 검증은 `./scripts/alert-policy-smoke.ps1`로 수행합니다.

production image 네 개의 CycloneDX SBOM 생성과 CRITICAL 취약점 0건 검증은 image build 후 `./scripts/container-security.ps1`로 재현합니다. CI의 SBOM은 commit SHA별 artifact로 30일 보관됩니다.

배송과 이벤트는 PostgreSQL에 같은 트랜잭션으로 기록됩니다. outbox publisher가 대기 이벤트를 Kafka에 전달하므로 broker가 일시 중단되어도 생성 이벤트가 유실되지 않습니다.

주문과 배송의 독립 lifecycle은 `./scripts/order-smoke.ps1`로 검증합니다. 이 테스트는 주문 생성 멱등성, 단일 배송 연결, `READY → DISPATCHED → FULFILLED`, 주문 outbox 이벤트 3종과 simulator 원상 복구를 확인합니다.

창고 흐름 검증은 `./scripts/warehouse-smoke.ps1`로 실행합니다. API는 `POST /api/warehouse/receipts`, `POST /api/warehouse/outbounds`, `POST /api/warehouse/outbounds/{id}/dispatch`와 재고·작업·ledger 조회를 제공합니다.

도로 경로와 ETA 흐름 검증은 `./scripts/route-smoke.ps1`로 실행합니다.

불변 GPS 이력 저장과 실제 주행 궤적 조회는 `./scripts/telemetry-track-smoke.ps1`로 검증합니다. `GET /api/telemetry/points`는 최근 5,000개 좌표를 최신순으로 반환하며 지도는 이를 시간순으로 연결해 계획 경로와 구분합니다. `/api/routes`와 `/api/telemetry/points`의 `deliveryIds` 조회 범위 및 응답 격리는 `./scripts/map-data-scope-smoke.ps1`로 검증합니다. 콘솔은 기본 `LIVE` 배송의 지도 데이터만 먼저 받고, `ALL` 전환 시 누락된 배송을 최대 100건씩 지연 로드합니다.

지연·경로 이탈 lifecycle과 운영자 확인은 `./scripts/alert-smoke.ps1`로 검증합니다. 활성 경고는 `POST /api/alerts/{id}/acknowledgement`와 `X-Operator` 헤더로 멱등 확인할 수 있으며, 콘솔에서도 미확인 경고 수와 최초 확인자를 표시합니다. 검증은 결정론적 telemetry 주입을 위해 simulator를 일시 중단한 뒤 자동으로 다시 시작합니다.

Redis 기반 다중 API SSE fan-out은 `./scripts/sse-fanout-smoke.ps1`로 검증합니다. 스크립트가 `scale-test` profile의 API replica를 8081 포트에 일시 실행하고 primary에서 발생한 배송 갱신과 단일 `telemetry-point`가 replica 구독자에게 전달되는지 확인한 뒤 종료합니다. 브라우저는 초기 궤적을 한 번 조회한 뒤 각 GPS 점을 event ID로 멱등 병합해 이벤트마다 전체 이력을 다시 받지 않습니다.

API에서 Python analytics까지 이어지는 trace는 `./scripts/tracing-smoke.ps1`로 검증합니다. 알려진 W3C trace ID를 주입하고 Tempo에서 두 서비스의 span을 직접 조회합니다.

PostgreSQL 일별 KPI projection과 CSV 보고서는 `./scripts/kpi-smoke.ps1`로 검증합니다. 고품질 PDF 보고서는 `GET /api/reports/daily-kpis.pdf?days=30` 또는 대시보드의 `DOWNLOAD PDF`에서 내려받으며, `./scripts/pdf-smoke.ps1`가 실제 PDF를 `output/pdf/logitrack-daily-kpi-report.pdf`에 생성해 검증합니다. 대시보드의 `Delivery performance` 패널은 최근 14일 지표를 30초마다 갱신합니다.

멱등 배송 생성 API의 20 RPS 기준선은 `./scripts/load-smoke.ps1`로 재현합니다. 99% 성공률과 p95 500ms 기준을 넘지 못하면 스크립트가 실패합니다.

DLQ 격리, 선택 replay, 감사 기록과 중복 방지는 `./scripts/replay-smoke.ps1`로 검증합니다. 영구 poison event는 replay 뒤 새 DLQ 항목으로 다시 격리되는 것이 정상입니다.

최대 20건 범위의 dry-run plan, 명시적 승인, 5 events/s 제한은 `./scripts/replay-plan-smoke.ps1`로 검증합니다.

Kafka telemetry 100건의 API 반영 p95와 consumer lag는 `./scripts/telemetry-load.ps1`로 측정합니다.

서로 다른 배송을 초당 100건 생성하는 최종 write-heavy 기준선은 `./scripts/load-unique-isolated.ps1`로 실행합니다. 별도 Compose project와 임시 PostgreSQL volume을 사용하고 성공률 99% 이상, p95 300ms 이하를 판정한 뒤 종료 시 자동 제거합니다.

분석 서비스, 단일 Kafka consumer, Redis 장애와 자동 복구는 `./scripts/recovery-drill.ps1`로 재현합니다. 스크립트는 장애 중 DB/Kafka 보존과 복구 후 정확히 한 번 반영을 확인하고 모든 서비스를 원상 복구합니다.

오래 열린 운영 탭의 배포 감지와 자동 새로고침은 `./scripts/runtime-version-smoke.ps1`로 검증합니다. 같은 웹 runtime에서는 식별자가 안정적이고 컨테이너 교체 후에는 바뀌어야 합니다.

# LogiTrack

실제 GPS 장비 없이 배송 차량, 창고, 주문의 상태 변화를 재현하는 이벤트 기반 물류 운영 플랫폼입니다.

## 첫 번째 수직 슬라이스

1. API로 배송을 생성합니다.
2. Spring Boot가 배송과 outbox 이벤트를 원자적으로 저장하고 `delivery.created.v1`을 Kafka에 발행합니다.
3. Python 경로 분석 서비스가 도로망 경로와 ETA 스냅샷을 만들고, 시뮬레이터가 경로상의 GPS 점을 `vehicle.telemetry.v1`로 발행합니다.
4. Spring Boot가 최신 위치와 배송 상태를 저장하고 SSE로 브라우저에 전송합니다.
5. Next.js 콘솔에서 진행 상태와 이벤트를 확인합니다.

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

샘플 배송 생성:

```bash
curl -X POST http://localhost:8080/api/deliveries \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: demo-001" \
  -d '{"orderNumber":"ORD-1001","vehicleId":"TRUCK-01","origin":{"name":"Seoul Hub","lat":37.5665,"lon":126.9780},"destination":{"name":"Incheon DC","lat":37.4563,"lon":126.7052}}'
```

상태 조회: `GET /api/deliveries`, 실시간 스트림: `GET /api/stream/deliveries`

경로 스냅샷 조회는 `GET /api/routes`입니다. 개발 환경은 OSRM 호환 endpoint를 사용하며 2.5초 안에 응답하지 않거나 오류가 발생하면 로컬 geodesic 계산으로 자동 전환합니다. 공개 demo는 개발용이므로 운영에서는 `.env`의 `OSRM_BASE_URL`을 자체 호스팅 또는 계약된 공급자로 교체하세요. 완전한 오프라인 실행은 `ROUTING_PROVIDER=geodesic`으로 설정합니다.

운영 콘솔은 MapLibre 기반 벡터 지도에서 계획 경로, 주행 완료 구간, 차량 상태와 ETA를 실시간으로 표시합니다. 기본 OpenFreeMap 스타일은 별도 API key 없이 동작하며, 운영용 지도 공급자는 `.env`의 `NEXT_PUBLIC_MAP_STYLE_URL`로 교체할 수 있습니다.

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
- [운영 및 장애 처리](docs/operations.md)
- [로컬 성능 기준선](docs/performance.md)
- [10분 데모 시나리오](docs/demo.md)
- [구현 진행 현황](docs/progress.md)

## 로컬 검증

```bash
python -m unittest discover simulator/tests
docker compose config
python -m unittest discover analytics/tests
```

통합 smoke test는 전체 스택 실행 후 `./scripts/smoke.ps1`로 수행합니다.

배송과 이벤트는 PostgreSQL에 같은 트랜잭션으로 기록됩니다. outbox publisher가 대기 이벤트를 Kafka에 전달하므로 broker가 일시 중단되어도 생성 이벤트가 유실되지 않습니다.

창고 흐름 검증은 `./scripts/warehouse-smoke.ps1`로 실행합니다. API는 `POST /api/warehouse/receipts`, `POST /api/warehouse/outbounds`, `POST /api/warehouse/outbounds/{id}/dispatch`와 재고·작업·ledger 조회를 제공합니다.

도로 경로와 ETA 흐름 검증은 `./scripts/route-smoke.ps1`로 실행합니다.

지연·경로 이탈 lifecycle 검증은 `./scripts/alert-smoke.ps1`로 실행합니다. 이 검증은 결정론적 telemetry 주입을 위해 simulator를 일시 중단한 뒤 자동으로 다시 시작합니다.

Redis 기반 다중 API SSE fan-out은 `./scripts/sse-fanout-smoke.ps1`로 검증합니다. 스크립트가 `scale-test` profile의 API replica를 8081 포트에 일시 실행하고 primary에서 발생한 이벤트가 replica 구독자에게 전달되는지 확인한 뒤 종료합니다.

API에서 Python analytics까지 이어지는 trace는 `./scripts/tracing-smoke.ps1`로 검증합니다. 알려진 W3C trace ID를 주입하고 Tempo에서 두 서비스의 span을 직접 조회합니다.

PostgreSQL 일별 KPI projection과 CSV 보고서는 `./scripts/kpi-smoke.ps1`로 검증합니다. 고품질 PDF 보고서는 `GET /api/reports/daily-kpis.pdf?days=30` 또는 대시보드의 `DOWNLOAD PDF`에서 내려받으며, `./scripts/pdf-smoke.ps1`가 실제 PDF를 `output/pdf/logitrack-daily-kpi-report.pdf`에 생성해 검증합니다. 대시보드의 `Delivery performance` 패널은 최근 14일 지표를 30초마다 갱신합니다.

멱등 배송 생성 API의 20 RPS 기준선은 `./scripts/load-smoke.ps1`로 재현합니다. 99% 성공률과 p95 500ms 기준을 넘지 못하면 스크립트가 실패합니다.

DLQ 격리, 선택 replay, 감사 기록과 중복 방지는 `./scripts/replay-smoke.ps1`로 검증합니다. 영구 poison event는 replay 뒤 새 DLQ 항목으로 다시 격리되는 것이 정상입니다.

최대 20건 범위의 dry-run plan, 명시적 승인, 5 events/s 제한은 `./scripts/replay-plan-smoke.ps1`로 검증합니다.

Kafka telemetry 100건의 API 반영 p95와 consumer lag는 `./scripts/telemetry-load.ps1`로 측정합니다.

서로 다른 배송을 지속 생성하는 write-heavy 기준선은 `./scripts/load-unique-isolated.ps1`로 실행합니다. 별도 Compose project와 임시 PostgreSQL volume을 사용하고 종료 시 자동 제거합니다.

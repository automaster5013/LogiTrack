# LogiTrack

실제 GPS 장비 없이 배송 차량, 창고, 주문의 상태 변화를 재현하는 이벤트 기반 물류 운영 플랫폼입니다.

## 첫 번째 수직 슬라이스

1. API로 배송을 생성합니다.
2. Spring Boot가 배송과 outbox 이벤트를 원자적으로 저장하고 `delivery.created.v1`을 Kafka에 발행합니다.
3. Python 시뮬레이터가 경로상의 GPS 점을 `vehicle.telemetry.v1`로 발행합니다.
4. Spring Boot가 최신 위치와 배송 상태를 저장하고 SSE로 브라우저에 전송합니다.
5. Next.js 콘솔에서 진행 상태와 이벤트를 확인합니다.

## 빠른 시작

요구 사항: Docker Desktop + Docker Compose v2

```bash
docker compose up --build
```

- 운영 콘솔: http://localhost:3000
- API health: http://localhost:8080/actuator/health
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3001 (`admin` / `admin`)

샘플 배송 생성:

```bash
curl -X POST http://localhost:8080/api/deliveries \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: demo-001" \
  -d '{"orderNumber":"ORD-1001","vehicleId":"TRUCK-01","origin":{"name":"Seoul Hub","lat":37.5665,"lon":126.9780},"destination":{"name":"Incheon DC","lat":37.4563,"lon":126.7052}}'
```

상태 조회: `GET /api/deliveries`, 실시간 스트림: `GET /api/stream/deliveries`

운영 콘솔은 MapLibre 기반 벡터 지도에서 계획 경로, 주행 완료 구간, 차량 상태와 ETA를 실시간으로 표시합니다. 기본 OpenFreeMap 스타일은 별도 API key 없이 동작하며, 운영용 지도 공급자는 `.env`의 `NEXT_PUBLIC_MAP_STYLE_URL`로 교체할 수 있습니다.

## 문서

- [요구사항과 성공 기준](docs/requirements.md)
- [8~10주 로드맵](docs/roadmap.md)
- [아키텍처 및 데이터 모델](docs/architecture.md)
- [기술 선택 ADR](docs/adr/0001-technology-stack.md)
- [실시간 지도 ADR](docs/adr/0002-live-map.md)
- [운영 및 장애 처리](docs/operations.md)
- [구현 진행 현황](docs/progress.md)

## 로컬 검증

```bash
python -m unittest discover simulator/tests
docker compose config
```

통합 smoke test는 전체 스택 실행 후 `./scripts/smoke.ps1`로 수행합니다.

배송과 이벤트는 PostgreSQL에 같은 트랜잭션으로 기록됩니다. outbox publisher가 대기 이벤트를 Kafka에 전달하므로 broker가 일시 중단되어도 생성 이벤트가 유실되지 않습니다.

창고 흐름 검증은 `./scripts/warehouse-smoke.ps1`로 실행합니다. API는 `POST /api/warehouse/receipts`, `POST /api/warehouse/outbounds`, `POST /api/warehouse/outbounds/{id}/dispatch`와 재고·작업·ledger 조회를 제공합니다.

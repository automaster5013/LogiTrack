# LogiTrack 10분 데모 시나리오

## 준비

```powershell
cd C:\LogiTrack
docker compose up -d --build
docker compose ps
```

- 운영 콘솔: `http://localhost:3000` 또는 `http://127.0.0.1:3000`
- Grafana: `http://localhost:3001` (`admin` / `.env`의 `GRAFANA_ADMIN_PASSWORD`)
- API readiness: `http://localhost:8080/actuator/health/readiness`

## 진행 순서

1. `+ SIMULATE DELIVERY`로 배송을 만들고 MapLibre 지도의 기본 `LIVE` 범위에서 실제 도로 geometry, 차량 이동, ETA와 선택 차량 halo를 확인한다. 검색으로 차량·주문·위치를 좁히면 지도와 telemetry 목록이 함께 필터링되고, `ALL`은 완료 이력까지 살펴볼 때 사용한다.
2. `Delivery performance`에서 UTC 일별 cohort, 정시율, 평균 cycle을 확인하고 CSV를 다운로드한다.
3. 창고에서 `RECEIVE 10` 후 `PICK & DISPATCH 4`를 실행해 stock, reserved, 불변 ledger를 설명한다.
4. `./scripts/alert-smoke.ps1`을 실행해 지연·경로 이탈 alert 발생·운영자 확인·중복 확인 멱등성·해결과 실시간 UI를 확인한다.
5. `Vehicle threshold policies`에서 전역 정책과 차량별 재정의를 비교하고 감사 이력의 `RESTORE`로 과거 임계값을 복원한다. `./scripts/alert-policy-smoke.ps1`로 저장·reset·복원과 감사 이력을 확인한다.
6. `./scripts/tracing-smoke.ps1` 결과의 trace ID를 Grafana Explore의 Tempo에서 조회해 Spring API→Python analytics span을 확인한다.
7. `./scripts/replay-smoke.ps1`을 실행하고 `Selective event replay`에서 poison event 격리, replay 상태, 운영자 감사를 확인한다.
8. `./scripts/load-smoke.ps1`과 `./scripts/telemetry-load.ps1`로 API p95와 Kafka 반영 p95/lag 기준선을 보여준다.
9. 기본 데이터를 보존한 고유 생성 시험이 필요하면 `./scripts/load-unique-isolated.ps1`을 실행한다.

## 핵심 설명

- PostgreSQL은 transactional source of truth이며 outbox, 부분 인덱스, 분석 집계와 향후 PostGIS 확장을 같은 운영 모델로 제공한다.
- 웹은 JavaScript가 아니라 TypeScript 기반 Next.js이며 배송·경로·경고·재고·KPI·DLQ payload를 정적 타입으로 관리한다.
- Kafka는 `deliveryId` key ordering과 at-least-once 전달을 사용하고 `processed_events`가 중복 side effect를 차단한다.
- Redis Pub/Sub은 API 인스턴스 간 SSE를 fan-out하며 장애 시 로컬 연결로 degrade한다.
- 외부 route provider 실패 시 deterministic geodesic 경로로 fallback한다.

## 검증 명령

```powershell
./scripts/smoke.ps1
./scripts/route-smoke.ps1
./scripts/alert-smoke.ps1
./scripts/alert-policy-smoke.ps1
./scripts/sse-fanout-smoke.ps1
./scripts/tracing-smoke.ps1
./scripts/kpi-smoke.ps1
./scripts/replay-smoke.ps1
./scripts/load-smoke.ps1
./scripts/telemetry-load.ps1
./scripts/load-unique-isolated.ps1
```

모든 smoke는 테스트용 데이터를 추가한다. `alert-smoke`, `alert-policy-smoke`, `telemetry-load`는 simulator를 일시 중지하고 `finally`에서 다시 시작한다. AWS/ReleasePilot 자원은 이 데모 범위에 포함하지 않는다.

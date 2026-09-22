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
pwsh ./scripts/init-env.ps1
docker compose up --build
```

`init-env.ps1`는 Git에서 제외된 `.env`에 PostgreSQL과 Grafana용 독립 난수 비밀번호를 생성하며 기존 파일은 덮어쓰지 않습니다. 영속 데이터를 유지한 자격 증명 회전은 실행 중인 스택에서 `./scripts/rotate-local-secrets.ps1`를 사용합니다. 두 비밀번호가 비어 있으면 Compose는 시작 전에 실패합니다. PostgreSQL 데이터베이스명과 사용자는 `.env`의 `POSTGRES_DB`, `POSTGRES_USER`로 변경할 수 있으며 API와 복제 인스턴스, 데이터베이스 healthcheck에 동일하게 적용됩니다.
웹과 관측성 서비스는 HTTP 응답으로, simulator는 Kafka 소비 루프 heartbeat로 준비 상태를 판정하므로 `docker compose up --wait`가 모든 장기 실행 서비스의 실제 동작 가능 상태까지 기다립니다.

- 운영 콘솔: http://localhost:3000 또는 http://127.0.0.1:3000
- API health: http://localhost:8080/actuator/health
- 경로 분석 health: http://localhost:8090/health
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3001 (`admin` / `.env`의 `GRAFANA_ADMIN_PASSWORD`)
- Tempo API: http://localhost:3200 (`Grafana → Explore → Tempo`에서 trace 조회)
- OpenTelemetry Collector health: http://localhost:13133

Compose가 공개하는 모든 개발용 포트는 호스트의 `127.0.0.1`에만 바인딩되므로 같은 네트워크의 다른 장치에서는 접근할 수 없습니다. 외부 공개 배포는 인증과 TLS를 갖춘 별도 ingress를 사용하세요.
컨테이너 간 통신도 `edge`, `data`, `analytics-egress`, `observability` 영역으로 분리됩니다. 웹은 API에만, 데이터 서비스는 필요한 API·simulator에만 연결되며 analytics와 관측성 구성 요소도 별도 영역에서 필요한 상대만 탐색할 수 있습니다. 개발용 host port를 유지하면서 불필요한 컨테이너 간 DNS·직접 연결 경로를 제거합니다.
Kafka JVM heap은 256~512 MiB로 고정해 1 GiB 컨테이너 상한 안에 native memory와 page cache 여유를 남깁니다. 기본·성능 Compose 검증과 runtime smoke가 이 간격을 회귀 검사합니다.

PostgreSQL 논리 백업은 `./scripts/postgres-backup.ps1`로 충돌 없는 이름의 dump와 SHA-256 sidecar를 만들고, `./scripts/postgres-restore.ps1 -BackupPath <dump> -TargetDatabase logitrack_restore -Force`로 무결성을 확인한 뒤 격리된 데이터베이스에 복원합니다. 복구 내용은 고유 staging DB에 먼저 완전히 적재되므로 검증·restore 실패가 기존 대상 DB를 훼손하지 않습니다. checksum이 없는 신뢰 가능한 기존 dump만 명시적 `-AllowUnverified`로 복원할 수 있습니다. `./scripts/postgres-backup-restore-smoke.ps1`는 연속 백업 경로의 고유성, 1바이트 변조 거부, 실패 시 기존 대상 보존·staging 정리, 스키마·sentinel 왕복 복원을 검증합니다.

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

주문 조회: `GET /api/orders`, 전체 주문 페이지 조회: `GET /api/orders/page?page=0&size=100`, 배송 목록·단건 조회: `GET /api/deliveries`, `GET /api/deliveries/{id}`, 전체 배송 페이지 조회: `GET /api/deliveries/page?page=0&size=100`, 전체 경고 페이지 조회: `GET /api/alerts/page?page=0&size=100`, 실시간 스트림: `GET /api/stream/deliveries`. 기존 목록과 범위 없는 경로 조회는 최신 200건이 기본이며 `limit=1..500`으로 조정합니다. 주문·배송·경고 페이지는 각각 `totalElements`와 `hasMore`를 제공하며 `page`는 0 이상, `size`는 1~500입니다. 기존 `POST /api/deliveries`는 호환성을 위해 유지하지만 신규 운영 흐름은 주문 생성 후 배차를 사용합니다.

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
python scripts/compose-config-smoke.py
python -m unittest discover analytics/tests
```

통합 smoke test는 전체 스택 실행 후 `./scripts/smoke.ps1`로 수행합니다.

`./scripts/compose-runtime-smoke.ps1`는 실행 중인 기본 스택과 선택적으로 활성화된 `scale-test` API replica의 health, loopback 포트, 로그 회전, 종료 유예, 자원 상한, 권한 경계, read-only filesystem, Kafka volume topology가 현재 Compose 정책과 일치하는지 확인합니다.

핵심 도메인의 line/branch coverage 80% gate는 `./scripts/domain-coverage.ps1`로 실행합니다. 현재 기준선은 line 92.37%, branch 88.71%이며 기준 미달 시 빌드가 실패합니다.

GitHub Actions의 `CI` workflow는 main push와 pull request마다 API 테스트·coverage gate, Python analytics/simulator 테스트, Docker Compose 구성 검증, TypeScript production build를 병렬 실행합니다. workflow 권한은 저장소 읽기로 제한됩니다.

배포 가능한 production image와 non-root runtime은 `./scripts/container-build.ps1`로 검증합니다. CD 1단계는 수동 승인된 GitHub `staging` environment와 AWS OIDC를 통해 기대 AWS 계정 ID 및 ECR의 immutable tag·scan-on-push·AES256 설정을 확인한 뒤 검증된 이미지를 commit SHA tag로 게시하고, ECR에서 확인한 digest와 GitHub workflow 실행 식별자를 고정한 release manifest를 보관합니다. 부분 게시 후 재실행할 때는 기존 immutable tag의 digest와 OCI revision provenance를 검증한 image만 안전하게 재사용합니다. 실제 AWS runtime 배포는 리전·비용 상한·비밀정보·rollback 정책 승인 후 연결합니다.

ECR repository 5개, Terraform destroy 차단, 최신 image 30개·미태그 7일 기본 보존 정책, Terraform caller와 OIDC provider 계정 일치 검증, 최소 권한 publisher role의 사전 구성은 `infra/aws/bootstrap` Terraform root에 정의되어 있습니다. CI는 format·provider 초기화·validate와 별도 trust-boundary smoke를 실행하지만, AWS 비용·리전·원격 state가 승인되기 전에는 plan/apply하지 않습니다.

차량별 경고 정책은 관제 화면의 `Vehicle threshold policies`에서 설정합니다. `GLOBAL DEFAULT`를 기준으로 차량별 경로 이탈(m)과 ETA 지연(s)의 `CLOSE < OPEN ≤ CRITICAL` 값을 재정의하며, `RESET TO GLOBAL`로 안전하게 상속 상태로 되돌릴 수 있습니다. 저장과 reset은 PostgreSQL 불변 감사 이력에 운영자와 함께 남고, `GET /api/alert-policies/audits/page`에서 누적 전체를 조회하며 각 감사 snapshot의 `RESTORE`로 과거 임계값을 다시 적용할 수 있습니다. 복원 자체도 `RESTORE` 감사 기록을 생성합니다. 종단 간 검증은 `./scripts/alert-policy-smoke.ps1`로 수행합니다.

production image 다섯 개의 CycloneDX SBOM 생성과 CRITICAL 취약점 0건 검증은 image build 후 `./scripts/container-security.ps1`로 재현합니다. SBOM은 CycloneDX 1.7 구조, 서비스별 image tag·digest, 구성요소 식별자와 현재 Git SHA provenance까지 검사한 뒤에만 업로드되며 CI artifact는 commit SHA별로 30일 보관됩니다.

배송과 이벤트는 PostgreSQL에 같은 트랜잭션으로 기록됩니다. outbox publisher가 대기 이벤트를 Kafka에 전달하므로 broker가 일시 중단되어도 생성 이벤트가 유실되지 않습니다.

20회 발행 실패로 격리된 outbox 이벤트는 관제 화면의 `Failed event recovery` 또는 `POST /api/operations/outbox/failures/{id}/retry`와 필수 `X-Operator` 헤더로 재시도합니다. 실패 목록과 outbox/DLQ 복구 감사 이력은 페이지 API로 누적 전체를 조회합니다. 재시도는 비관적 잠금 아래 `PENDING`으로 초기화되고 불변 운영자 감사 이력을 남기며 `./scripts/outbox-recovery-smoke.ps1`로 검증합니다.

주문과 배송의 독립 lifecycle은 `./scripts/order-smoke.ps1`로 검증합니다. 이 테스트는 주문 생성 멱등성, 단일 배송 연결, `READY → DISPATCHED → FULFILLED`, 주문 outbox 이벤트 3종과 simulator 원상 복구를 확인합니다.

창고 흐름 검증은 `./scripts/warehouse-smoke.ps1`로 실행합니다. API는 `POST /api/warehouse/receipts`, `POST /api/warehouse/outbounds`, `POST /api/warehouse/outbounds/{id}/dispatch`와 재고·작업·ledger 조회를 제공합니다. 누적 이력은 `GET /api/warehouse/stock/page`, `/tasks/page`, `/ledger/page`에서 안정 정렬된 페이지로 조회할 수 있습니다.

도로 경로와 ETA 흐름 검증은 `./scripts/route-smoke.ps1`로 실행합니다. 1KB 이상의 JSON·GeoJSON·CSV 응답은 gzip 협상을 지원하며 `./scripts/response-compression-smoke.ps1`가 경로 응답의 압축 헤더와 50% 이상 전송량 절감을 검증합니다.

API의 정확한 CORS 허용 출처는 쉼표 구분 `CORS_ALLOWED_ORIGINS`로 설정합니다. 기본값은 로컬 콘솔의 두 주소인 `http://localhost:3000,http://127.0.0.1:3000`이며, 와일드카드와 HTTP(S) origin 이외의 값은 시작 시 거부합니다. API와 웹의 클릭재킹·MIME 스니핑·referrer·브라우저 권한 제한 헤더 및 신뢰하지 않는 출처 차단은 `./scripts/http-boundary-smoke.ps1`로 검증합니다. HTTPS의 HSTS는 TLS를 종료하는 배포 계층에서 설정합니다.

API의 기본 HTTP 수용량은 Tomcat worker 128개, 동시 연결 512개, 대기 요청 100개로 제한하며 연결 수립 5초·keep-alive 20초·연결당 요청 100개의 상한을 둡니다. 배포 환경에서 `SERVER_MAX_THREADS`, `SERVER_MAX_CONNECTIONS`, `SERVER_ACCEPT_COUNT`와 관련 timeout 변수를 조정할 수 있고, 실제 적용값은 Prometheus의 `tomcat_threads_config_max_threads` 및 `tomcat_connections_config_max_connections` 지표로 확인합니다.

Kafka telemetry consumer 부재 경보는 유휴 상태에서 생성되지 않을 수 있는 lag 지표가 아니라 consumer의 partition assignment 지표 자체가 사라졌는지를 사용하므로, 입력이 잠시 없을 때 오탐하지 않습니다.

GPS simulator는 delivery event 처리 시작 시 API에서 현재 진행률을 확인하고 이미 적용된 step을 건너뜁니다. 따라서 simulator 재시작이나 수동 telemetry 부하 검증 후에도 진행률을 0부터 다시 발행해 DLQ를 오염시키지 않습니다.

DLQ 단건·batch replay smoke는 의도적으로 잘못된 payload가 다시 격리되는 것까지 확인한 뒤 해당 실행의 원본·재격리 row와 연관 감사를 제거하므로, 반복 검증 자체가 운영 backlog 경보를 누적시키지 않습니다.

API readiness는 필수 source of truth인 PostgreSQL 연결을 포함합니다. Redis 장애는 로컬 SSE fallback으로 계속 서비스하되 PostgreSQL 장애는 HTTP 503 readiness로 트래픽 유입을 중단하며, `./scripts/readiness-smoke.ps1`가 두 장애와 자동 복구를 검증합니다.

모든 HTTP API 응답은 `X-Trace-Id`를 반환합니다. 호출자가 1~128자의 안전한 식별자를 보내면 보존하고, 없으면 생성해 controller와 로그 MDC에 전달합니다. 경계 동작은 `./scripts/request-trace-smoke.ps1`로 검증합니다.

불변 GPS 이력 저장과 실제 주행 궤적 조회는 `./scripts/telemetry-track-smoke.ps1`로 검증합니다. `GET /api/telemetry/points`는 최근 5,000개 좌표를 최신순으로 반환하며 지도는 이를 시간순으로 연결해 계획 경로와 구분합니다. `deliveryIds` 범위 조회도 총 5,000개 상한을 유지하되 요청한 각 배송의 최신 좌표를 우선 포함해 고빈도 차량이 다른 차량의 현재 위치를 밀어내지 않습니다. `/api/routes`와 `/api/telemetry/points`의 조회 범위 및 응답 격리는 `./scripts/map-data-scope-smoke.ps1`로 검증하며, 범위 경로 조회는 배송별 최신 스냅샷 하나만 반환합니다. 콘솔은 기본 `LIVE` 배송의 지도 데이터만 먼저 받고, `ALL` 전환 시 누락된 배송을 최대 100건씩 지연 로드합니다.

지연·경로 이탈 lifecycle과 운영자 확인은 `./scripts/alert-smoke.ps1`로 검증합니다. 활성 경고는 `POST /api/alerts/{id}/acknowledgement`와 `X-Operator` 헤더로 멱등 확인할 수 있으며, 콘솔에서도 미확인 경고 수와 최초 확인자를 표시합니다. 검증은 결정론적 telemetry 주입을 위해 simulator를 일시 중단한 뒤 자동으로 다시 시작합니다.

Redis 기반 다중 API SSE fan-out은 `./scripts/sse-fanout-smoke.ps1`로 검증합니다. 스크립트가 `scale-test` profile의 API replica를 8081 포트에 일시 실행하고 primary에서 발생한 배송 갱신과 단일 `telemetry-point`가 replica 구독자에게 전달되는지 확인한 뒤 종료합니다. 브라우저는 초기 궤적을 한 번 조회한 뒤 각 GPS 점을 event ID로 멱등 병합해 이벤트마다 전체 이력을 다시 받지 않으며, SSE 재연결 시 누락 가능 구간을 읽기 전용 API snapshot으로 다시 동기화합니다.

API에서 Python analytics까지 이어지는 trace는 `./scripts/tracing-smoke.ps1`로 검증합니다. 알려진 W3C trace ID를 주입하고 Tempo에서 두 서비스의 span을 직접 조회합니다.

PostgreSQL 일별 KPI projection과 CSV 보고서는 `./scripts/kpi-smoke.ps1`로 검증합니다. 고품질 PDF 보고서는 `GET /api/reports/daily-kpis.pdf?days=30` 또는 대시보드의 `DOWNLOAD PDF`에서 내려받으며, `./scripts/pdf-smoke.ps1`가 실제 PDF를 `output/pdf/logitrack-daily-kpi-report.pdf`에 생성해 검증합니다. 대시보드의 `Delivery performance` 패널은 최근 14일 지표를 30초마다 갱신합니다.

멱등 배송 생성 API의 20 RPS 기준선은 `./scripts/load-smoke.ps1`로 재현합니다. 99% 성공률과 p95 500ms 기준을 넘지 못하면 스크립트가 실패합니다.

DLQ 격리, 선택 replay, 감사 기록과 중복 방지는 `./scripts/replay-smoke.ps1`로 검증합니다. 영구 poison event는 replay 뒤 새 DLQ 항목으로 다시 격리되는 것이 정상입니다.

재처리할 수 없는 DLQ 이벤트는 Control Tower의 `DISCARD` 작업으로 필수 사유와 운영자를 기록해 backlog에서 제외할 수 있습니다. 상태 전이는 단방향이며 실제 폐기·감사·중복 요청 거부는 `./scripts/dlq-discard-smoke.ps1`로 검증합니다.

여러 건을 폐기할 때는 `POST /api/operations/discard-plans`로 최대 20건의 dry-run 계획을 만들고, 10분 안에 같은 운영자가 `X-Discard-Approval: DISCARD`로 실행합니다. 중복 ID 제거, 승인값, 부분 실패와 단일 실행 보장은 `./scripts/discard-plan-smoke.ps1`로 검증합니다.

Control Tower에서도 PENDING 이벤트를 최대 20건 선택해 공통 사유를 입력하고 계획을 검토할 수 있습니다. 실행 버튼은 운영자가 `DISCARD`를 정확히 입력해야 활성화되며, 실행 전에는 계획을 취소해 선택과 입력을 초기화할 수 있습니다.

최대 20건 범위의 dry-run plan, 명시적 승인, 5 events/s 제한은 `./scripts/replay-plan-smoke.ps1`로 검증합니다.

Kafka telemetry 100건의 API 반영 p95와 consumer lag는 `./scripts/telemetry-load.ps1`로 측정합니다.

서로 다른 배송을 초당 100건 생성하는 최종 write-heavy 기준선은 `./scripts/load-unique-isolated.ps1`로 실행합니다. 별도 Compose project와 임시 PostgreSQL volume을 사용하고 성공률 99% 이상, p95 300ms 이하를 판정한 뒤 종료 시 자동 제거합니다.
성능 스택도 외부 이미지를 digest로 고정하고 API를 loopback에만 공개하며, CPU·메모리·PID·로그·권한·임시 저장소 상한을 적용합니다. PostgreSQL·Redis·Kafka의 data 영역과 analytics 영역은 외부 egress가 없는 내부 네트워크이고, API만 부하 발생기의 host 접근을 위한 runner 네트워크를 추가로 사용합니다. `python scripts/perf-compose-config-smoke.py`가 이 격리 경계를 CI에서 검증합니다.

분석 서비스, 단일 Kafka consumer, Redis 장애와 자동 복구는 `./scripts/recovery-drill.ps1`로 재현합니다. 스크립트는 장애 중 DB/Kafka 보존과 복구 후 정확히 한 번 반영을 확인하고 모든 서비스를 원상 복구합니다.

오래 열린 운영 탭의 배포 감지와 자동 새로고침은 `./scripts/runtime-version-smoke.ps1`로 검증합니다. 같은 웹 runtime에서는 식별자가 안정적이고 컨테이너 교체 후에는 바뀌어야 합니다.

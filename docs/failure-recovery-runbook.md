# 장애 주입 및 복구 runbook

## 목적

로컬 환경에서 외부 경로 분석, Kafka consumer, Redis fan-out 장애를 안전하게 재현하고 PostgreSQL과 Kafka가 보존한 상태로 정상 복구되는지 검증한다. 실제 운영 데이터나 클라우드 자원은 사용하지 않는다.

## 자동 훈련

전체 Compose 스택이 정상인 상태에서 다음 명령을 실행한다.

```powershell
./scripts/recovery-drill.ps1
```

스크립트는 진행 중 자동 위치 이벤트의 간섭을 막기 위해 simulator를 잠시 중지하며, 성공·실패와 관계없이 중지한 서비스를 `finally`에서 다시 시작한다.

### 1. analytics 장애

1. analytics 컨테이너를 중지한다.
2. 배송 생성 API를 호출한다.
3. 배송과 route snapshot이 PostgreSQL에 기록되고 provider가 `spring-fallback`인지 확인한다.
4. analytics를 시작하고 `/health`가 200으로 복구되는지 확인한다.

판정: 외부 경로 공급/분석 장애가 배송 command를 막지 않고 fallback 사용 사실이 snapshot에 남아야 한다.

analytics 재시작 직후 OpenTelemetry batch exporter의 첫 flush는 지연될 수 있다. 분산 추적 회귀 검증은 최대 60초 동안 Tempo를 조회한다.

### 2. consumer 강제 종료

1. control API 컨테이너를 `KILL` signal로 종료한다.
2. API가 없는 동안 정상 telemetry를 Kafka에 발행한다.
3. API를 다시 시작하고 readiness를 기다린다.
4. 보존된 이벤트가 배송 진행률에 반영되고 `processed_events`에 정확히 한 번 기록되는지 확인한다.

판정: 단일 consumer 프로세스 장애 중 이벤트가 유실되지 않고 재시작 뒤 자동 처리되어야 한다.

### 3. Redis 장애

1. Redis를 중지한다.
2. 배송을 생성하고 telemetry를 발행한다.
3. PostgreSQL 배송 상태가 계속 갱신되는지 확인한다.
4. `logitrack_sse_fallback_total{reason="redis_error"}` 증가를 확인한다.
5. Redis를 시작하고 API readiness가 `UP`으로 돌아오는지 확인한다.

판정: Redis는 실시간 fan-out 계층이며 DB write path의 source of truth가 아니다. 장애 중 현재 API 인스턴스의 로컬 SSE로 degrade하고, 복구 뒤 Redis listener가 재연결되어야 한다.

Redis 연결과 명령 timeout은 각각 기본 2초(`REDIS_CONNECT_TIMEOUT`, `REDIS_COMMAND_TIMEOUT`)로 제한한다. 이 경계를 초과하면 Kafka consumer가 fan-out을 기다리지 않고 로컬 fallback으로 전환한다.

## 실패 시 수동 복구

```powershell
docker compose start redis analytics api simulator
docker compose ps
./scripts/smoke.ps1
```

- API가 준비되지 않으면 PostgreSQL, Kafka, Redis health 순서로 확인한다.
- consumer 반영이 없으면 `vehicle.telemetry.v1`의 consumer group lag와 API 로그를 확인한다.
- Redis 복구 뒤에도 readiness가 내려가 있으면 API 로그의 listener 재연결 여부를 확인하고 API만 재시작한다.
- analytics 복구 뒤 신규 route가 계속 fallback이면 analytics 로그와 OSRM timeout을 확인한다.

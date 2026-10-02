# 로컬 운영과 장애 처리

## 프로덕션 데이터 고가용성 기준선

프로덕션 인프라의 비적용 Terraform 기준선은 `infra/aws/production-state`, `infra/aws/production-alerting`, `infra/aws/production-audit`, `infra/aws/production-certificates`, `infra/aws/production-data`, `infra/aws/production-compute`, `infra/aws/production-edge`에 분리되어 있다. 알림 계층은 서울 서비스 경보와 버지니아 엣지 경보를 회전형 고객 관리 KMS 키로 각각 암호화하고, 계정·리전·경보 이름이 제한된 CloudWatch 발행과 확인 완료된 HTTPS 페이징 수신자만 허용한다. 감사 계층은 모든 리전의 관리 이벤트를 KMS 암호화하고 무결성 검증하며 S3 Object Lock compliance mode로 400일 이상 변경 불가능하게 보존하고, 루트 계정 사용과 권한 거부 급증을 paging한다. 데이터 계층은 세 Availability Zone의 private subnet에 암호화된 RDS PostgreSQL Multi-AZ, 2노드 Valkey Multi-AZ automatic failover와 3브로커 MSK를 구성한다. 컴퓨트 계층은 같은 세 AZ에 API/analytics와 web Fargate task를 최소 3개씩 배치하고, 검증된 CloudFront 요청만 전달하는 ALB, AZ별 NAT, PrivateLink endpoint, secret JSON-key 주입, 자동 rollback과 autoscaling을 적용한다. 엣지 계층은 동적 응답 caching을 끈 dual-stack CloudFront, global WAF managed rule·viewer IP rate limit, TLS 1.2 및 전역 경보를 구성한다. 이 root들은 비용과 데이터 이전 위험 때문에 CI에서 validate만 하며 자동 apply하지 않는다. 적용 전 보호된 원격 state bootstrap, 예산, 승인된 HTTPS 페이징 수신자와 구독 확인, viewer/origin ACM 인증서, 감사 보존기간의 법무·보안 승인, 복원·failover·부하 훈련, migration/cutover 및 rollback 계획을 별도 승인해야 한다.

실제 적용 전에는 [프로덕션 cutover gate](production-cutover.md)의 증적 manifest를 작성하고 동일 main revision에 대해 검증한다. 이 검증은 승인된 변경 창과 apply 권한을 대체하지 않는다.

## 로컬 자격 증명

최초 실행 전에 `./scripts/init-env.ps1`로 Git에서 제외된 `.env`를 생성한다. PostgreSQL과 Grafana는 서로 다른 256-bit 난수 비밀번호를 사용하며 빈 값이나 저장소의 공개 기본값으로 기동할 수 없다. 영속 볼륨을 유지하면서 회전할 때는 스택이 healthy인 상태에서 `./scripts/rotate-local-secrets.ps1`를 실행한다. 이 스크립트는 두 서비스의 저장된 자격 증명을 먼저 갱신하고 `.env`를 교체한 뒤 PostgreSQL·API·Grafana를 새 설정으로 재생성한다.

## Health와 관측성

Prometheus의 모든 경보는 [경보 대응 runbook](alert-runbooks.md)의 개별 절차로 연결된다. 운영자는 경보 annotation의 `runbook_url`에서 영향, 즉시 조치, 진단, 종료 및 에스컬레이션 기준을 바로 확인한다.

Grafana의 `LogiTrack Alert Triage` 대시보드는 활성 critical·warning과 pending 경보, 영향받은 component, component별 firing 수, 활성 instance와 최근 6시간 timeline, rule evaluation 실패, Alertmanager readiness와 전달 실패를 한 화면에 제공한다. 모든 경보는 `alerting`, `api`, `demo`, `outbox`, `recovery`, `reporting`, `retention`, `routing`, `telemetry` 중 하나로 분류해 알림 routing에도 같은 taxonomy를 사용한다.

Prometheus는 경보를 내부 `alertmanager:9093`으로 전달한다. Alertmanager는 `alertname`, `component`, `severity`로 중복 경보를 그룹화하고 critical은 30분, warning은 4시간 간격으로 반복 처리한다. 같은 component의 critical이 활성화되면 하위 warning을 억제해 연쇄 장애 노이즈를 줄인다. 상태와 silence UI는 로컬 `http://127.0.0.1:9093`에서만 접근할 수 있고 상태는 전용 volume에 보존된다. 기본 receiver는 lifecycle 검증용 내부 receiver다. 외부 paging은 저장소 밖의 HTTPS URL 비밀 파일을 `ALERTMANAGER_CRITICAL_WEBHOOK_URL_FILE`로 지정하고 `python scripts/alertmanager-paging-secret-smoke.py <파일>`로 검증한 다음 `docker compose -f docker-compose.yml -f docker-compose.paging.yml up -d alertmanager prometheus`로 명시적으로 활성화한다. 이 경계는 critical만 외부로 보내고 복구 알림도 전송하며 redirect와 100건 초과 payload를 차단한다. 실제 destination과 자격 증명은 저장소에 넣지 않는다.

Prometheus는 Alertmanager `/metrics`도 별도 job으로 수집한다. 2분간 scrape가 끊기면 critical, 마지막 구성 reload가 실패하면 warning, Prometheus에서 Alertmanager로 전달한 경보가 실패하거나 drop되면 warning을 발생시킨다. 이 세 control-plane 경보는 `alerting` component로 분류한다.

- API liveness/readiness: `/actuator/health/liveness`, `/actuator/health/readiness`. Readiness는 애플리케이션 상태와 PostgreSQL을 포함하며 Redis는 로컬 SSE fallback이 있으므로 제외한다.
- HTTP 요청에서 생성한 outbox 이벤트는 원래 W3C trace context를 함께 저장하고 비동기 Kafka producer span의 parent로 복원한다. `./scripts/outbox-trace-smoke.ps1`는 PostgreSQL 저장, 발행 완료, Tempo의 동일 trace 연결을 왕복 검증하고 fixture를 정리한다.
- CORS는 `CORS_ALLOWED_ORIGINS`의 exact HTTP(S) origin과 `Authorization`, `Content-Type`, `Idempotency-Key`, `X-Trace-Id`, `X-Operator`, `X-Replay-Approval`, `X-Discard-Approval` 요청 헤더만 허용한다. 기본 origin은 `http://localhost:3000,http://127.0.0.1:3000`이며 와일드카드·경로·자격 증명·쿼리·fragment가 포함된 값은 시작 시 거부한다. 허용 preflight는 1시간 캐시하며 그 밖의 임의 사용자 정의 헤더는 거부한다. 브라우저 BFF와 로그아웃은 POST·DELETE에서 일치하는 `Origin` 또는 same-origin/none `Sec-Fetch-Site`를 요구하며, 교차 출처뿐 아니라 두 출처 신호가 모두 누락된 요청도 API 전달이나 쿠키 변경 전에 403으로 거부한다.
- 웹 응답의 Content Security Policy는 default-deny를 적용해 same-origin 자산·빌드 시 확정된 API 및 지도 origin·MapLibre blob worker만 명시 허용한다. 각 HTML 응답은 암호학적 난수 nonce와 `strict-dynamic`으로 Next.js 부트스트랩 스크립트만 허용하고 production `script-src`에서 `unsafe-inline`과 `unsafe-eval`을 모두 제거한다. 스타일시트 요소도 same-origin 또는 동일 nonce만 허용하며, 지도 위치·진행률처럼 제한된 동적 요소 속성만 `style-src-attr`로 분리해 허용한다. staging의 same-origin BFF 빌드는 loopback origin을 포함하지 않으며 frame·object·media를 차단한다.
- 웹은 opener와 resource policy를 same-origin으로 격리하고 별도 origin agent cluster를 요청해 다른 origin의 browsing context와 메모리·opener 관계를 분리한다. 웹과 API 모두 legacy cross-domain policy discovery를 차단한다.
- API 보안 헤더는 애플리케이션 filter와 Spring Security header writer가 같은 정책을 사용해 실제 응답에서도 base·form·frame·object 제한이 축소되지 않도록 한다.
- API의 요청 검증·상태 충돌 예외에 내부 원인이 연결된 경우 원인과 wrapper 메시지는 서버 로그에만 남기고 외부 응답에는 상태별 일반 메시지와 trace ID만 반환한다.
- 운영자 인증을 활성화한 웹은 `OIDC_REDIRECT_URI`가 없으면 요청의 Host 기반 origin으로 대체하지 않고 인증 요청·redirect·CSRF origin 검사를 즉시 실패시킨다. 요청 origin fallback은 `AUTH_REQUIRED`가 꺼진 로컬 개발 모드에서만 허용한다.
- API 보안은 환경변수가 없어도 기본 활성화되어 issuer·client ID가 없으면 시작에 실패한다. staging 웹과 API는 동일한 필수 `COGNITO_CLIENT_ID`를 각각 인증 교환과 access token 검증에 사용한다. 로컬 loopback Compose만 인증 비활성화와 명시적인 개발용 client ID를 함께 선언하며, non-loopback CORS origin에서는 비활성 모드가 시작되지 않는다. 데이터베이스 비밀번호도 기본값 없이 `DB_PASSWORD`가 필수다. API는 JWT `roles` claim의 `VIEWER`, `OPERATOR`, `RECOVERY_OPERATOR`, `ADMIN`만 권한으로 인정하며 감사 actor는 검증된 token subject로 덮어써 클라이언트 `X-Operator` 위조를 차단한다.
- 운영 보안 모드의 관리 표면은 `/actuator/health/**`만 공개하고 `info`, `prometheus`를 포함한 나머지 `/actuator/**`와 정의되지 않은 비-API 경로는 유효한 JWT가 있더라도 명시적으로 거부한다. 로컬 loopback의 인증 비활성 모드에서만 Compose 관측 스택의 Prometheus 수집을 허용한다.
- 주문·배송·위치·감사·복구·보고서를 포함한 모든 `/api/**` 응답은 `Cache-Control: no-store`로 브라우저와 중간 프록시 저장을 금지한다. 웹 정적 자산과 actuator의 별도 cache 정책은 변경하지 않는다.
- 모든 `/api/**` 요청은 API 인스턴스별 고정 구간 속도 제한을 적용한다. 기본값은 인증 주체 또는 로컬 비인증 모드의 직접 연결 주소별 분당 300건이며 `HTTP_RATE_LIMIT_REQUESTS`, `HTTP_RATE_LIMIT_WINDOW_SECONDS`, `HTTP_RATE_LIMIT_MAX_SUBJECTS`로 조정한다. 제한 응답은 `429`, `Retry-After`, `RateLimit-*` 헤더를 반환하고 클라이언트가 제공한 전달 주소 헤더는 신뢰하지 않는다.
- PostgreSQL 연결 획득은 기본 3초(`DB_CONNECTION_TIMEOUT_MS`), 연결 검증은 2초(`DB_VALIDATION_TIMEOUT_MS`) 안에 실패한다. DB 장애 중 요청·consumer·예약 작업이 JDBC 기본 30초 대기로 누적되는 것을 막고, 연결 풀이 복구되면 별도 재시작 없이 다시 처리한다.
- analytics health: `http://localhost:8090/health`
- Prometheus scrape: `/actuator/prometheus`
- OpenTelemetry Collector health: `http://localhost:13133/`
- Tempo readiness: `http://localhost:3200/ready`

로컬 Compose 포트는 모두 `127.0.0.1`에만 게시된다. 데이터베이스, 브로커, API, 관측 도구를 LAN이나 공용 인터페이스에 직접 노출하지 말고 외부 배포에서는 인증과 TLS가 적용된 ingress를 사용한다.

모든 Compose 서비스는 Docker `json-file` 로그를 파일당 10 MiB, 최대 3개로 회전한다. `docker compose logs --since 30m <service>`로 최근 로그를 확인하며, 장기 보존이 필요하면 중앙 로그 수집기를 별도로 연결한다.

모든 장기 실행 서비스는 종료 신호 후 35초의 유예를 받는다. 이는 Spring의 최대 30초 graceful shutdown 단계와 데이터베이스·브로커의 flush를 마칠 시간을 제공하며, 유예가 지나면 Docker가 강제 종료해 무한 대기를 방지한다.

## PostgreSQL backup/restore

`./scripts/postgres-backup.ps1`는 실행 중인 PostgreSQL에서 owner/ACL 비종속 custom-format dump를 `output/backups/`에 생성하고, 컨테이너 안에서 archive 목차를 검증한 뒤 `<dump>.sha256` 무결성 sidecar를 만든다. 복원은 `./scripts/postgres-restore.ps1 -BackupPath <dump> -TargetDatabase logitrack_restore -Force`를 사용하며 DB를 변경하기 전에 sidecar의 파일명과 SHA-256을 검증한다. checksum이 없는 신뢰 가능한 기존 dump만 `-AllowUnverified`로 명시적으로 허용한다. 안전을 위해 온라인 도구는 기본 `logitrack` DB 덮어쓰기를 거부하며, 검증 DB에서 확인한 뒤 유지보수 창에 연결 문자열을 전환한다. `./scripts/postgres-backup-restore-smoke.ps1`는 1바이트 변조본 거부와 고유 sentinel 행의 임시 DB 복원을 모두 확인한 다음 원본 sentinel, 임시 DB, dump·sidecar를 제거한다.
- 로그 필드: timestamp, level, logger, message, trace/correlation 식별자
- 주요 지표: API latency/error, Kafka consumer lag, telemetry 처리량, DLQ 수, 활성 SSE 연결

Grafana Explore에서 `Tempo` datasource를 선택해 service name 또는 trace ID로 조회한다. 로컬은 모든 trace를 sampling하며 운영 환경에서는 `TRACING_SAMPLING_PROBABILITY`를 트래픽과 비용에 맞게 조정한다. Collector 장애는 요청 처리를 막지 않으며 exporter가 bounded queue와 retry를 사용한다.

모든 API 응답의 `X-Trace-Id`는 지원 문의와 HTTP 로그 상관관계에 사용한다. 호출자가 보내지 않으면 API가 UUID를 생성하고, 허용 문자 밖의 값이나 128자 초과 값은 400으로 거부한다. 애플리케이션 로그의 `requestId` MDC에도 같은 값이 기록된다.

잘못된 caller trace ID를 거부할 때도 API가 새 안전한 UUID를 응답 header와 표준 오류 body에 함께 넣어 해당 거부 응답 자체를 추적할 수 있다.

API 오류 body는 `error`, `traceId`, `timestamp`를 공통으로 반환한다. 중복 키·DB 제약 및 동시 수정 충돌은 내부 엔티티·SQL 정보를 노출하지 않는 409, 잘못된 JSON·필수 요청값 누락·타입 불일치는 400, 없는 리소스·경로는 404, 지원하지 않는 메서드는 405, 미디어 타입은 415로 변환한다.

POST·PUT·PATCH body는 스트리밍 읽기 단계에서 기본 1MB로 제한하며 초과 시 413을 반환한다. `HTTP_MAX_REQUEST_BODY_SIZE`로 조정할 수 있고 1 byte 미만 설정은 시작 시 거부한다.

API 요청과 Kafka 이벤트가 공유하는 Jackson parser는 중복 object key를 허용하지 않고 JSON 중첩 깊이를 기본 100단계로 제한한다. `JSON_MAX_NESTING_DEPTH`로 더 낮출 수 있지만 자원 고갈 방지를 위해 1~200 범위를 벗어난 설정은 시작 시 거부한다. 동일한 필드를 여러 값으로 반복하거나 과도하게 중첩한 JSON은 HTTP 400 또는 consumer 재시도·DLQ 경로로 거부한다. 또한 DTO로 역직렬화하는 HTTP 요청과 내부 응답은 계약에 선언되지 않은 필드, 첫 JSON 값 뒤에 이어지는 추가 값, 문자열을 숫자·불리언으로 바꾸는 스칼라 강제 변환, 실수를 정수로 줄이는 숫자 강제 변환, 원시 숫자·불리언 필드의 `null`을 HTTP 400 또는 호출 실패로 거부한다. tree 방식으로 읽는 Kafka 이벤트는 기존 schema·version 검증 경계를 따른다.

Tomcat은 애플리케이션 필터보다 먼저 처리하는 요청 line·header를 기본 8 KiB로 제한한다. form post와 거부 후 삼키는 body도 각각 1 MiB, 응답 header도 8 KiB로 제한한다. 환경 변수로 조정할 수 있지만 요청 header 16 KiB, 응답 header 32 KiB, body 처리 10 MiB를 넘거나 1 byte 미만이면 API가 시작되지 않아 HTTP 파서 단계의 자원 고갈 설정 drift를 차단한다.

브라우저의 인증 proxy도 `Content-Length`와 실제 body를 각각 1 MiB로 제한해 API에 도달하기 전 과대 요청을 413으로 거부한다. 내부 API의 일반 JSON·CSV·PDF 응답은 선언된 길이와 실제 streaming byte를 각각 16 MiB로 제한하며, 초과 응답은 취소하고 cache 불가 502 또는 연결 종료로 차단한다. 무기한 연결이 계약인 `text/event-stream`만 이 누적 크기 제한에서 제외한다. 내부 API 요청은 15초 후 중단하고 redirect를 따르지 않으며, 연결 실패·timeout은 cache 불가 502 응답으로 정규화한다.

예상하지 못한 예외는 상세 내용을 응답에 노출하지 않는 500으로 변환하고, 동일한 trace ID와 stack trace를 서버 로그에 기록한다.

5분 동안 API 5xx 응답이 5회를 초과하면 `LogiTrackApiServerErrors` warning이 발생한다. 해당 시간대 로그를 응답 trace ID로 좁혀 원인을 확인한다.

HTTP 요청은 100ms, 250ms, 500ms, 1s, 2s, 5s SLO bucket으로 집계한다. 전체 API p95가 2초를 5분간 초과하면 `LogiTrackApiLatencyHigh` warning이 발생한다.

외부 API 가용성 SLO는 30일 기준 99.9%로 정의하며 actuator 자체 점검 요청은 계산에서 제외한다. Prometheus는 5분·30분·1시간·6시간의 5xx 비율을 recording rule로 계산한다. 5분과 1시간 창이 동시에 오류 예산의 14.4배 속도로 소진되면 `LogiTrackApiErrorBudgetFastBurn` critical, 30분과 6시간 창이 동시에 6배 속도로 소진되면 `LogiTrackApiErrorBudgetSlowBurn` warning을 발생시킨다. 짧은 일시 오류와 장기 저강도 회귀를 분리하면서 단일 창의 순간 노이즈만으로 호출하지 않는다.

Grafana의 `LogiTrack API Availability SLO` 대시보드는 30일 가용성, 남은 오류 예산, 비점검 요청 처리량, 빠른·느린 소진 경보 상태와 네 시간창의 burn rate를 함께 제공한다. 파일 provisioning으로 읽기 전용 배포되며 30초마다 갱신된다.

배송·주문·텔레메트리 좌표는 위도 -90~90, 경도 -180~180 범위의 유한 실수만 허용하고 텔레메트리 진행률은 0~1로 제한한다. `NaN`, 무한대, 범위 밖 값은 도메인 검증에서 거부하며 PostgreSQL CHECK 제약이 저장 경로도 이중 방어한다.

Kafka 텔레메트리는 `eventType=vehicle.telemetry.v1`, 정수 `schemaVersion=1`, 배송과 일치하는 `vehicleId`, JSON number 좌표·진행률, 발생 시각을 요구한다. 문자열 숫자나 지원하지 않는 계약 버전은 정상 이벤트로 강제 변환하지 않고 재시도 후 DLQ로 격리한다. 발생 시각의 미래 허용 오차는 기본 5분이며 `TELEMETRY_MAX_FUTURE_SKEW`로 조정한다.

telemetry `traceId`도 HTTP와 같은 1~128자 안전 문자만 허용한다. 없으면 이벤트당 UUID를 한 번 생성해 배송, 경고, 주문 후속 처리 전체에 동일하게 전파한다.

운영자 OIDC 콜백은 authorization code와 state 길이를 제한하고 state를 상수 시간으로 비교한다. Cognito token 교환은 10초, JWKS 조회는 5초 안에 끝나야 하며 token 응답은 `application/json`만 허용하고 선언 길이와 실제 streaming body 모두 64 KiB를 넘으면 거부한다. ID token은 RS256 서명·issuer·audience·nonce·`token_use=id`·최근 발급을, access token은 RS256 서명·issuer·`token_use=access`·app client ID·1~120자이며 경계 공백과 제어 문자가 없는 subject·만료 여유·60초 미래 발급 허용 오차·정방향 발급/만료 순서·최대 61분 수명을 검증하고 두 token의 subject가 일치할 때만 세션 쿠키를 만든다. OAuth state·nonce·PKCE verifier와 access token은 모두 `__Host-` 쿠키로 발급해 `Secure`, 루트 path, Domain 속성 금지 경계를 브라우저가 강제하며 쿠키 수명은 검증된 access token의 실제 남은 수명을 넘지 않는다. 운영 콘솔 진입과 BFF의 내부 API 전달 전에도 같은 access token 검증을 반복하며 위조·만료 쿠키는 즉시 제거한다. API resource server도 같은 RS256·용도·client ID·subject·발급 시각·수명 경계를 독립적으로 재검증한다. redirect 응답은 따라가지 않고, 운영 환경의 issuer·authorization·callback URL은 자격 증명·query·fragment가 없는 HTTPS URL만 허용한다.

access token 세션은 `__Host-` prefix, `Secure`, `HttpOnly`, `Path=/`, `SameSite=Lax`를 사용해 하위 도메인 cookie 주입을 차단한다. 기존 `lt_access_token` 세션은 검증에 성공한 첫 page/BFF 요청에서 남은 token 수명 이내로 host-bound cookie에 이동하고 즉시 삭제되며, 위조·로그아웃 경로는 두 이름을 모두 만료시킨다.

텔레메트리가 적용할 수 있는 상태는 `IN_TRANSIT`, `DELAYED`, `DELIVERED`이며 `CREATED`로의 회귀는 거부한다. `DELIVERED`는 terminal 상태라 이후 이벤트는 위치 이력만 보존한다.

배송 행의 `lastTelemetryAt`보다 오래되거나 같은 시각의 replay 이벤트는 불변 GPS 이력에는 저장하지만 현재 배송 상태·ETA, 경고 평가, 주문 완료 판단에는 적용하지 않는다. 워터마크는 기존 이력의 최대 `occurredAt`으로 migration backfill되며, 이벤트마다 최신 이력을 재조회하지 않는다. 따라서 운영자가 늦은 DLQ 이벤트를 복구해도 관제 상태가 과거로 회귀하지 않고 같은 timestamp의 도착 순서에 따라 상태가 흔들리지 않는다.

`logitrack_telemetry_events_total{outcome="applied|stale"}`에서 현재 상태에 적용된 이벤트와 워터마크 때문에 이력에만 보존된 이벤트를 구분해 확인할 수 있다.

일별 KPI는 UTC 배송 생성일 cohort 기준으로 공개 API 최대 범위인 최근 90일을 트래픽 수락 전에 초기화하고, 첫 주기 실행은 설정된 간격만큼 기다린 뒤 이후 기본 60초마다 갱신한다. Compose에서는 primary API만 `LOGITRACK_REPORTS_WRITER_ENABLED=true`이고 scale-test replica는 `false`이다. Production ECS에서는 모든 API replica가 writer를 활성화하지만 refresh transaction이 PostgreSQL advisory lock을 먼저 획득하므로 한 replica만 projection을 갱신하고 나머지는 `logitrack.kpi.projection.refresh.skipped`를 증가시킨다. 원본 배송은 90일 범위로 제한하고 최초 route snapshot은 배송별 index lookup으로 읽으므로 전체 경로 이력을 매번 정렬하지 않는다. `GET /api/reports/daily-kpis?days=14`는 JSON, `GET /api/reports/daily-kpis.csv?days=30`은 UTF-8 CSV, `GET /api/reports/daily-kpis.pdf?days=30`은 A4 가로형 운영 보고서를 반환하며 요청 범위는 1~90일이다. 모든 보고서 GET은 projection을 읽기만 하고 범위 밖 요청은 조용히 보정하지 않고 400으로 거부한다. PDF는 API가 PostgreSQL projection을 조회한 뒤 analytics 서비스의 ReportLab 렌더러에 전달하므로 PDF만 실패할 때는 먼저 `http://localhost:8090/health`와 analytics 로그를 확인한다.

Primary writer는 마지막 성공 시각과 설정 주기를 `logitrack_kpi_projection_last_success_timestamp_seconds`, `logitrack_kpi_projection_refresh_interval_seconds`로 노출한다. 마지막 성공이 설정 주기의 3배를 초과하면 `LogiTrackKpiProjectionStale` warning이 발생하므로 API 로그와 PostgreSQL 상태를 확인한다.

공개 route provider 보호와 반복 경로 응답 안정화를 위해 analytics는 동일 좌표 결과를 기본 300초 캐시한다. `ROUTING_CACHE_TTL_SECONDS`로 조정하며 최대 1,024개 bounded LRU에서 가장 오래 사용하지 않은 항목만 축출한다. TTL 0은 캐시를 비활성화한다.

동일 좌표의 동시 cache miss는 하나의 in-flight OSRM 작업을 공유하고, 서로 다른 좌표는 전역 lock 없이 병렬 처리한다. 한 HTTP caller가 취소되어도 shield된 공유 작업과 다른 waiter는 계속 완료되며, 모든 waiter가 사라져도 background finalizer가 task를 정리하고 결과를 캐시한다. analytics 프로세스는 하나의 `httpx.AsyncClient` connection pool을 재사용하고 graceful shutdown 시 닫는다.

analytics는 OSRM 응답의 2~10,000개 유한 경위도 좌표와 양수 유한 거리·시간을 검증하고 위반 시 geodesic fallback을 사용한다. `ROUTING_PROVIDER`는 `osrm|geodesic`, `ROUTING_TIMEOUT_SECONDS`는 0초 초과 30초 이하, cache TTL은 0~86,400초만 허용한다. analytics가 정상 응답으로 반환한 `geodesic-fallback`도 API fallback counter와 경보에 포함된다.

API→analytics 호출은 경로 분석 connect/read 1초/4초, PDF connect/read 1초/15초로 제한한다. 각각 `ANALYTICS_ROUTE_*_TIMEOUT`, `ANALYTICS_REPORT_*_TIMEOUT` 환경변수로 조정하며 경로 timeout은 geodesic fallback으로 전환된다.

route/report timeout은 양수, PDF 응답 한도는 최소 5 bytes, telemetry 미래 허용 오차는 0 이상이어야 하며 안전하지 않은 설정이면 API가 시작을 거부한다.

KPI PDF 응답은 `%PDF` 서명과 기본 10MB 크기 상한을 모두 통과해야 전달한다. 상한은 `ANALYTICS_REPORT_MAX_RESPONSE_SIZE`로 조정할 수 있다.

PDF 렌더링 성공·실패는 `logitrack_report_pdf_total{outcome="success|failure"}`로 확인한다. 10분 동안 2회를 초과해 실패하면 `LogiTrackPdfRenderingFailing` warning이 발생하며 analytics health와 timeout, 응답 크기 제한을 함께 확인한다.

경로 분석 결과는 `logitrack_route_analysis_total{outcome="success|fallback"}`로 집계한다. 5분 동안 fallback이 5회를 초과하면 `LogiTrackRouteAnalysisDegraded` warning이 발생하므로 analytics health와 로그, 외부 route provider 상태를 순서대로 확인한다.

analytics 응답은 저장 전에 경로 ID, DB 길이에 맞는 provider·algorithm과 SHA-256 hash, 생성·도착 시각 순서, 2~10,000개 좌표, 유한한 경위도 범위, 양수 거리·소요 시간을 검증한다. 생성 시각은 서버보다 5분을 초과해 미래일 수 없다. HTTP 성공이어도 이 계약을 위반하면 `spring-fallback`으로 전환하고 fallback counter를 증가시킨다.

## 주문 운영

- 생성: `POST /api/orders`와 필수 `Idempotency-Key`; 주문은 배송 없이 `READY`로 저장된다.
- 조회: `GET /api/orders`; 연결된 배송 ID, 차량, 배송 상태도 함께 반환한다.
- 배차: `POST /api/orders/{id}/dispatch`와 필수 `Idempotency-Key`, body `{"vehicleId":"TRUCK-01"}`. 같은 주문에는 배송을 한 건만 연결한다.
- lifecycle topic: `order.created.v1`, `order.dispatched.v1`, `order.fulfilled.v1`.
- 배송 완료 telemetry가 적용되는 동일 트랜잭션에서 연결 주문을 `FULFILLED`로 바꾸고 완료 outbox 이벤트를 기록한다. PostgreSQL이 주문/배송 상태의 source of truth다.
- 검증: `./scripts/order-smoke.ps1`는 simulator를 잠시 중단해 결정론적 완료 telemetry를 발행하고 종료 시 반드시 복구한다.

## 실패 시나리오

- simulator 중단: 배송 생성/조회는 유지되며 위치 갱신만 정지한다. 재시작 후 새 이벤트부터 처리한다.
- 외부 route provider 중단/지연: analytics가 제한 시간 뒤 geodesic fallback으로 전환하며 provider 필드에 fallback 사용을 기록한다.
- 경로 이탈/지연: 활성 경고는 배송·유형별 하나로 병합되고 정상 범위 복귀 시 `RESOLVED`로 남는다. 운영자는 콘솔의 `ACKNOWLEDGE` 또는 `POST /api/alerts/{id}/acknowledgement`와 `X-Operator` 헤더로 활성 경고를 확인한다. 최초 확인자와 시각은 변경 불가능한 감사 정보로 남고, 중복 요청은 추가 이벤트를 만들지 않는다. 상태 전이 이벤트는 outbox에서 `delivery.alert.v1`으로 발행된다.
- 경고 임계값: `GET /api/alert-policies`에서 전역(`*`)·차량별 정책을 조회하고 `POST /api/alert-policies`와 필수 `X-Operator`·`Idempotency-Key`로 저장한다. 저장 응답이 유실된 같은 키·운영자·본문의 재시도는 완료 당시 정책이 그대로일 때 기존 결과를 반환하고 UPSERT 감사를 중복 기록하지 않으며, 같은 키의 다른 요청이나 이후 정책 변경 뒤 도착한 오래된 재시도는 충돌로 거부한다. `DELETE /api/alert-policies/{vehicleId}`는 차량 정책을 soft reset해 전역값 상속으로 되돌리며 전역 정책 삭제는 거부한다. reset 응답이 유실된 뒤 같은 운영자가 재시도하면 이미 비활성화된 정책을 성공으로 반환하고 감사를 중복 기록하지 않으며, 다른 운영자의 후속 reset은 충돌로 거부한다. 차량별 정책이 없으면 전역값을 사용하고 `CLOSE < OPEN ≤ CRITICAL` 순서를 API와 DB가 모두 검증한다. `GET /api/alert-policies/audits`는 `UPSERT`·`RESET`·`RESTORE` 최근 50개 불변 snapshot을 반환하며, `POST /api/alert-policies/audits/{auditId}/restore`와 필수 `X-Operator`로 선택한 snapshot을 다시 활성 정책으로 적용한다. RESTORE 감사는 원본 audit ID와 운영자를 고정하므로 응답 유실 뒤 같은 요청은 현재 정책이 그대로일 때만 기존 결과를 반환하며, 이후 정책 변경 뒤 도착한 오래된 재시도는 충돌로 거부한다. `./scripts/alert-policy-smoke.ps1`는 재정의의 경고 억제, 멱등 저장·reset·복원과 감사 3건을 검증한다.
- 계약·식별자·소유권·시간 형식이 잘못된 telemetry처럼 재시도로 회복할 수 없는 오류는 즉시 `vehicle.telemetry.dlq.v1`로 격리한다. DB·네트워크 같은 일시 오류만 제한된 exponential backoff를 거친다.
- DLQ replay/discard: 단건 복구는 필수 `Idempotency-Key`를 감사 레코드에 영구 결속하고 이벤트 row를 비관적으로 잠그므로 동시 요청 중 하나만 발행 또는 폐기·감사된다. 같은 키·운영자·이벤트·작업 의도의 재시도는 저장된 결과를 200으로 반환하고, 키의 다른 요청 재사용은 409로 거부한다. `./scripts/replay-concurrency-smoke.ps1`로 경쟁 조건을 검증한다.
- Kafka 중단: DB 조회/생성은 유지하고 생성 이벤트는 outbox에 남는다. publisher가 최대 20회 재시도하며 이후 `FAILED` 상태는 관제 화면 또는 `POST /api/operations/outbox/failures/{id}/retry`와 `X-Operator`, `Idempotency-Key`로 재처리한다. 동일 키·운영자·이벤트 재시도는 현재 결과를 반환하고, 키의 다른 요청 재사용과 실패 상태가 아닌 이벤트의 새 재처리는 충돌로 거부한다. 최근 실패·재시도 감사는 각각 `/api/operations/outbox/failures`, `/api/operations/outbox/retry-audits`에서 조회한다.
- outbox publisher는 한 poll에서 기본 최대 20건을 처리하되 `FOR UPDATE SKIP LOCKED`로 이벤트를 한 건씩 선택하고 각 발행을 독립 `REQUIRES_NEW` 트랜잭션으로 완료한다. 따라서 Kafka 대기나 실패가 다른 batch row의 잠금·rollback 범위를 늘리지 않으며 여러 API 인스턴스가 서로 다른 due 이벤트를 처리할 수 있다. 이벤트별 Kafka 응답은 기본 최대 5초이며 `OUTBOX_BATCH_SIZE`는 1~100, `OUTBOX_PUBLISH_TIMEOUT`은 0초 초과 30초 이하만 허용한다.
- 실패한 PENDING 이벤트는 1초부터 시작해 최대 5분인 지수 backoff의 `nextAttemptAt` 이후에만 다시 잠근다. 20회 실패 후 `FAILED`가 되며 운영자 retry는 시도 수를 초기화하고 즉시 재처리 대상으로 만든다.
- Redis 중단: DB가 source of truth이며 cache miss로 처리한다. SSE 다중 인스턴스 fan-out은 degraded 상태가 되지만 API readiness는 유지한다.
- DB 중단: API readiness가 실패하고 Kafka consumer가 재시도한다. broker의 이벤트는 보존된다.
- 창고 출고 확정: warehouse task 행을 먼저 비관적으로 잠가 동시 요청을 멱등 `DISPATCHED` 응답으로 직렬화하며 재고·ledger·outbox는 한 번만 변경한다. `./scripts/warehouse-dispatch-concurrency-smoke.ps1`로 검증한다.
- 최초 창고·SKU 재고 행 생성은 해당 문자열 키의 PostgreSQL transaction advisory lock으로 직렬화한다. 서로 다른 idempotency key의 동시 입고도 unique 충돌 없이 각각 한 번 합산되며 `./scripts/warehouse-receipt-concurrency-smoke.ps1`로 검증한다.
- 입고·피킹 요청 수량은 1~1,000,000으로 제한하며 DB 제약도 같은 범위를 강제한다. 누적 재고가 32비트 저장 범위를 넘으려 하면 변경 없이 409로 거부한다.
- SSE 연결은 인스턴스당 기본 1,000개(`SSE_MAX_CONNECTIONS`, 허용 범위 1~10,000), 인증 주체 또는 로컬 직접 연결 주소당 기본 5개(`SSE_MAX_CONNECTIONS_PER_SUBJECT`)로 제한한다. 초과 연결은 429로 거부하고 `logitrack_sse_rejected_total{reason="capacity|subject_capacity"}`에 기록한다. 주체 식별에는 클라이언트 전달 주소 헤더를 사용하지 않으며 연결 완료·타임아웃·오류·종료 시 점유량을 회수한다. heartbeat는 1~60초 범위만 허용한다.
- Analytics PDF 렌더러는 요청당 1~90개 UTC 일별 행만 허용하고 건수·비율·기간 값을 유효 범위로 제한해 직접 호출에서도 CPU·메모리 사용을 경계 짓는다.
- Analytics ASGI 수신 스트림은 기본 2MB(`ANALYTICS_MAX_REQUEST_BODY_BYTES`, 허용 범위 1KB~10MB)로 제한한다. Content-Length와 chunked body 모두 파싱 전에 누적 크기를 검사해 413으로 거부한다.
- 배송·텔레메트리·경고 SSE payload는 트랜잭션 안에서 스냅샷하고 DB 커밋 성공 후에만 Redis fan-out으로 발행한다. 롤백된 변경이 UI에 먼저 보이는 phantom update를 방지한다.
- Outbox, 복구 지표, KPI projection, retention 스케줄 간격은 시작 시 안전 범위를 검증한다. 1ms busy loop나 하루를 넘는 실수 설정은 애플리케이션 시작을 실패시켜 조용한 자원 고갈·정리 중단을 방지한다.
- CI의 공식 GitHub Actions는 immutable commit SHA로 고정하고 Dependabot이 매주 공식 action 업데이트를 묶어서 제안한다. 컨테이너 취약점 스캐너도 digest 고정을 유지한다.
- DLQ 재발행 실패 응답은 Kafka broker 주소·내부 예외를 노출하지 않는 고정 메시지를 사용하며 상세 원인은 서버 로그에 event ID와 함께 남긴다. Kafka 대기 중 interrupt는 복원해 정상적인 종료 신호를 보존한다.
- DB는 outbox, 창고 task/ledger, 배송 경고, DLQ replay·discard, replay 감사·plan의 enum 값과 상태별 timestamp·수량 불변식을 CHECK 제약으로 방어한다. `./scripts/data-integrity-smoke.ps1`은 현재 migration의 제약 집합과 잘못된 상태 거부, immutable ledger·감사 기록을 검증한다.

## 복구 큐 경보

API는 `logitrack_outbox_backlog{status="pending|failed"}`, `logitrack_outbox_oldest_age_seconds`, `logitrack_dlq_backlog` gauge를 10초마다 갱신한다. 조회 실패 시 마지막 정상 값을 유지하고 `logitrack_recovery_metrics_refresh_failures_total`을 누적하며, 로그는 장애·복구 전환에 한 번씩만 남긴다. Prometheus는 API scrape 1분 중단 또는 FAILED outbox 2분 지속 시 critical, metric refresh 실패·pending outbox 100건 초과·가장 오래된 pending 5분 초과·DLQ 존재·경로 fallback 반복·PDF 반복 실패·API 5xx 반복·p95 latency 상승·보존 정리 실패 시 warning을 발생시킨다. 데모 자동 보충이 활성화된 환경에서는 완료 이력 정리 건수·실패·감시 시작·마지막 성공 시각과 활성·목표 차량 수·보충 실패를 별도 지표로 제공한다. 정리 첫 실행 누락·실패·15분 정체와 실시간 데모 차량이 목표보다 2분간 적은 상태를 경고한다. Kafka client metric을 이용해 telemetry partition lag 합계가 100건을 5분간 넘으면 warning, consumer partition metric이 2분간 사라지면 critical을 발생시킨다. `./scripts/recovery-metrics-smoke.ps1`로 지표 노출, 17개 규칙 로드, 데모 정리·차량 부족 경보 시나리오를 함께 검증한다.

가장 오래된 outbox 나이는 payload 전체 행을 읽지 않고 PostgreSQL `MIN(created_at)` scalar 집계로 계산한다.

운영자 복구 처리량은 `logitrack_outbox_retries_total`과 `logitrack_dlq_replays_total` counter로 확인한다. 두 counter는 감사 저장까지 성공한 요청만 증가한다.

전체 장애 주입 절차와 수동 복구 명령은 [장애 주입 및 복구 runbook](failure-recovery-runbook.md)에 있다. `./scripts/recovery-drill.ps1`는 analytics fallback, consumer 강제 종료 중 Kafka buffering, Redis degraded fan-out을 순서대로 검증하며 모든 중지 서비스를 `finally`에서 재시작한다.

Redis 장애가 Kafka consumer 트랜잭션을 오래 점유하지 않도록 연결과 명령 timeout은 기본 2초다. `REDIS_CONNECT_TIMEOUT`, `REDIS_COMMAND_TIMEOUT`으로 조정할 수 있으며, timeout 뒤에는 `reason="redis_error"` fallback 지표가 증가한다.

웹 콘솔은 `GET /api/runtime-version`을 15초마다 확인한다. 웹 컨테이너가 교체되어 runtime version이 바뀌면 열린 탭이 자동 새로고침되어 이전 정적 CSS/JavaScript를 계속 사용하는 상황을 방지한다. 탭이 백그라운드에 있다가 다시 보이면 즉시 한 번 확인한다. `./scripts/runtime-version-smoke.ps1`는 같은 runtime의 값이 안정적인지, 재시작 뒤 값이 바뀌는지 검증한다.

## SSE fan-out 운영

- Redis channel: `logitrack.stream.v1` (`STREAM_CHANNEL`로 변경 가능)
- 인스턴스 식별: `INSTANCE_ID`; SSE `connected` 이벤트에 포함
- 지표: `logitrack_sse_connections`, `logitrack_sse_redis_published_total`, `logitrack_sse_redis_received_total`, `logitrack_sse_fallback_total`
- Redis 장애 중에는 이벤트를 처리한 API의 로컬 구독자만 갱신된다. PostgreSQL 상태는 계속 최신이므로 클라이언트 재연결/조회로 복구하며, Redis가 돌아오면 listener container가 재구독한다.
- 브라우저 새로고침이나 네트워크 전환으로 클라이언트가 먼저 연결을 닫는 정상 상황은 500 오류로 집계하거나 JSON 오류 본문을 쓰지 않고 debug 수준에서 종료한다.
- API는 기본 15초(`SSE_HEARTBEAT_MS`)마다 SSE comment heartbeat를 보내 유휴 프록시 연결을 유지하고 끊어진 emitter를 제거한다. `./scripts/sse-heartbeat-smoke.ps1`는 connected 이벤트와 20초 내 keepalive 수신을 검증한다.
- 애플리케이션 종료 이벤트에서는 열린 SSE emitter를 모두 완료해 graceful shutdown이 무기한 stream을 기다리지 않게 한다.

## DLQ 재처리 정책

원본 payload, 오류 유형, 최초/최종 실패 시간, trace ID를 보존한다. 운영자가 원인을 수정하고 event ID를 새로 만들지 않은 채 replay하여 consumer 멱등성을 검증한다. 자동 무한 replay는 금지한다.

## 데이터 보존

PostgreSQL, Redis, Kafka, Tempo, Prometheus, Grafana의 가변 상태는 각각 명시적인 Compose named volume에 저장한다. 일반적인 `docker compose down`과 컨테이너 재생성은 데이터를 유지한다. `docker compose down --volumes`는 업무 데이터와 관측 이력을 함께 영구 삭제하므로 CI 격리 환경 또는 명시적인 초기화가 필요할 때만 사용한다.

Kafka broker 로그만 `kafka-data`에 영속화한다. 이미지가 선언하지만 현재 broker 로그로 사용하지 않는 `/etc/kafka/secrets`, `/mnt/shared/config`, `/var/lib/kafka/data`는 각각 16 MiB tmpfs로 제한해 재생성마다 익명 Docker volume이 누적되지 않게 한다.

모든 장기 실행 서비스에는 역할별 CPU·메모리 상한이 있다. API는 2 CPU/1.5 GiB, Kafka는 1.5 CPU/1 GiB를 허용하고 나머지는 0.5~1 CPU/256~768 MiB 범위다. OOM 또는 throttling이 반복되면 `docker stats`와 서비스 로그를 먼저 확인하고 부하 기준선을 다시 측정한 뒤 상한을 조정한다.

모든 Compose 컨테이너는 `no-new-privileges`를 사용한다. 이미지 안의 setuid/setgid 실행 파일이나 파일 capability를 이용한 추가 권한 획득을 차단하며, 구성 smoke test가 서비스 추가 시 이 경계를 강제한다.

API, analytics, simulator, web, OpenTelemetry Collector는 Linux capability를 모두 제거하고 root filesystem을 읽기 전용으로 실행한다. 런타임 임시 파일은 서비스별 64~128 MiB `/tmp` tmpfs에만 기록할 수 있어 이미지 변조와 무제한 임시 파일 증가를 제한한다.

- 처리 완료 event ID와 GPS 이력은 기본 30일, PUBLISHED outbox는 7일 보존한다. Kafka 기본 보존보다 긴 멱등성 창을 유지하며 PENDING/FAILED outbox, DLQ, replay·정책·복구 감사와 업무 aggregate는 자동 삭제하지 않는다.
- 정리 작업은 5분마다 테이블별 최대 1,000건만 오래된 순서로 삭제해 긴 트랜잭션과 vacuum 부담을 제한한다. `FOR UPDATE SKIP LOCKED`로 여러 API 인스턴스의 정리 작업이 같은 행에서 대기하지 않는다. 보존 기간은 `PROCESSED_EVENT_RETENTION`, `PUBLISHED_OUTBOX_RETENTION`, `TELEMETRY_RETENTION`, batch는 `RETENTION_BATCH_SIZE`로 조정하며 기간은 최소 하루, batch는 1~10,000만 허용한다.
- `./scripts/retention-smoke.ps1`는 테스트 행 삽입 후 API를 재시작해 initial-delay 기준의 정리 주기를 결정론적으로 시작하고, 만료 행 삭제와 최근 행 보존을 검증한다.
- `logitrack_retention_deleted_total{table=...}`에서 커밋된 실제 정리량을 확인하고 `logitrack_retention_failures_total`로 실패를 추적한다. cutoff 전용 부분/정렬 인덱스로 전체 테이블 scan을 피한다.
- Published outbox가 보존 기한을 지나 삭제될 때 연결된 재시도 감사 행도 FK cascade로 함께 제거한다. 감사 FK가 전체 retention 트랜잭션을 막거나 고아 이력을 남기지 않으며 retention smoke가 이 경로를 포함한다.
- 재처리 완료 DLQ와 연결 replay audit은 기본 90일(`REPLAYED_DLQ_RETENTION`) 후 bounded batch로 함께 삭제한다. 미처리 `PENDING` DLQ는 자동 삭제하지 않는다.
- 운영자가 폐기한 `DISCARDED` DLQ와 연결 감사도 같은 90일 보존 정책을 적용한다. 최대 20건의 일괄 폐기는 dry-run 계획, 10분 승인 창, 동일 운영자, 정확한 `X-Discard-Approval: DISCARD` 값을 요구한다.
- Replay plan batch 설정은 1~100개로 제한한다. 잘못된 대규모 설정이 단일 실행에서 장시간 DB connection과 plan lock을 점유하지 못하게 한다.
- 콘솔의 주문·KPI·복구 큐·정책 poller는 이전 요청 완료 후 다음 타이머를 예약한다. API 지연이나 장애 시 interval 요청이 중첩되어 회복 중인 서버를 더 압박하지 않는다.
- GPS simulator는 기본 8개 worker와 최대 16개 실행/대기 slot만 허용한다. interval·step·worker 범위와 작업당 최대 120초를 시작 시 검증하며, malformed delivery 이벤트나 개별 simulation 실패가 consumer 프로세스를 종료하지 않는다. 기본 `SIMULATION_RESUME_FROM_API=true`에서는 현재 진행률을 API에서 읽어 재개하고, 인증이 활성화된 staging은 simulator 자격 증명을 두지 않은 채 `false`로 고정해 신규 outbox 이벤트를 0%부터 처리한다.
- 출발지와 목적지가 같거나 1m 미만인 요청도 fallback 경로 거리를 최소 1m로 정규화한다. route snapshot의 양수 거리 DB 불변식을 지키면서 지역 내 배송을 500/409로 실패시키지 않는다.
- Analytics PDF 응답은 전체를 메모리에 적재한 뒤 검사하지 않고 설정 상한+1 byte까지만 스트리밍으로 읽는다. 응답 상한 설정도 5 byte~50MB로 제한해 잘못된 값이 JVM heap을 무제한 노출하지 않는다.
- 경로 분석 JSON도 기본 2MB(`ANALYTICS_ROUTE_MAX_RESPONSE_SIZE`, 허용 범위 1KB~10MB) 상한+1 byte까지만 읽고 역직렬화한다. 초과·비정상 응답은 기존 로컬 geodesic fallback으로 안전하게 전환한다.

- 목록: 호환용 최신 100건은 `GET /api/operations/dlq?status=PENDING`, 전체 backlog 탐색은 `GET /api/operations/dlq-page?status=PENDING&page=0&size=100`을 사용한다. page는 0 이상, size는 1~100이며 응답의 `totalElements`와 `hasMore`로 다음 페이지를 판단한다. Control Tower는 최신 100건을 먼저 표시하고 필요할 때 오래된 페이지를 추가 로드한다. `./scripts/dlq-pagination-smoke.ps1`는 PENDING 행을 변경하지 않고 모든 페이지의 중복·누락 여부를 DB count와 대조한다.
- 단일 replay/discard: `POST /api/operations/dlq/{id}/replay|discard`와 필수 `X-Operator`, `Idempotency-Key` 헤더
- 감사: `GET /api/operations/replay-audits`
- 동일 catalog 항목은 한 번만 replay할 수 있다. 영구 오류가 다시 DLQ로 가면 새 항목으로 조사한다.

### 선택 범위 replay

1. `POST /api/operations/replay-plans`에 `{"eventIds":[...]}`와 `X-Operator`, `Idempotency-Key`를 보내 dry-run plan을 만든다. 응답 유실 재시도에는 같은 키·운영자·event ID 목록을 사용하며 기존 plan을 반환한다. 같은 키의 다른 요청은 충돌로 거부한다.
2. 응답의 대상과 10분 만료 시각을 검토한다.
3. `POST /api/operations/replay-plans/{id}/execute`에 같은 `X-Operator`와 `X-Replay-Approval: APPROVE`를 보낸다.

### 선택 범위 폐기

1. `POST /api/operations/discard-plans`에 `{"eventIds":[...],"reason":"..."}`와 `X-Operator`, `Idempotency-Key`를 보내 최대 20건의 dry-run 계획을 만든다. 응답 유실 재시도에는 같은 키·운영자·event ID 목록·사유를 사용하며 기존 plan을 반환한다. 같은 키의 다른 요청은 충돌로 거부한다.
2. 응답의 대상, 공통 폐기 사유와 10분 만료 시각을 검토한다.
3. `POST /api/operations/discard-plans/{id}/execute`에 같은 `X-Operator`와 `X-Discard-Approval: DISCARD`를 보낸다.
4. 각 성공 항목은 `DISCARDED` 상태와 개별 감사 행을 남기며, 이미 처리된 항목은 실패 수에 포함된다. 응답 유실 뒤 같은 운영자와 승인으로 계획을 다시 실행하면 저장된 결과를 반환하고 항목이나 감사를 중복 처리하지 않는다.

기본 최대 20건, 5 events/s이며 각각 `logitrack.replay.batch-max-size`, `logitrack.replay.batch-rate-per-second`로 조정한다. plan 잠금과 단방향 상태 전이는 동시 실행의 중복 부작용을 막고, 완료된 동일 실행의 재요청에는 저장된 결과를 반환하며 이벤트별 감사 행을 유지한다.

batch 최대 크기는 양수, 처리율은 1~1,000 events/s여야 하며 범위를 벗어난 설정은 조용히 보정하지 않고 API 시작을 거부한다.

batch의 각 이벤트 replay는 독립 `REQUIRES_NEW` 트랜잭션이다. 한 이벤트가 발행 실패해 rollback되어도 앞선 성공 이벤트와 감사는 유지되고 plan은 성공·실패 수를 `EXECUTED` 또는 `PARTIAL`로 기록한다.

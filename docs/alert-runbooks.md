# Prometheus 경보 대응 runbook

이 문서는 LogiTrack 운영 경보의 첫 대응 절차다. 경보를 확인한 운영자는 발생 시각, 경보 이름, 현재 값, 배포 revision을 사건 기록에 남기고 아래 절차를 따른다. 데이터 삭제, DLQ 폐기, 데이터베이스 복원, rollback은 원인과 복구 지점을 확인한 뒤 실행한다.

공통 확인 명령:

```powershell
docker compose ps
Invoke-RestMethod http://localhost:9090/api/v1/alerts
Invoke-RestMethod http://localhost:8080/actuator/health
Invoke-RestMethod http://localhost:8080/actuator/prometheus
docker compose logs --since 15m api
```

공개 staging 장애에서는 `https://www.logitrack.kr/api/runtime-version`의 revision을 GitHub `main` 및 최근 배포 SHA와 먼저 대조한다. 경보가 복구돼도 원인을 확인하지 못했거나 반복되면 사건을 종료하지 않는다.

## LogiTrackApiErrorBudgetFastBurn

- 영향: 99.9% 가용성 오류 예산이 빠르게 소진되어 약 2일 안에 월간 예산을 모두 사용할 위험이 있다.
- 즉시 조치: 신규 배포와 비필수 변경을 중단하고 현재 5xx, API health, 최근 배포 SHA를 확인한다. 배포 직후 시작됐다면 검증된 직전 digest로 rollback한다.
- 진단: `http_server_requests_seconds_count`를 URI와 status로 나눠 실패 경로를 찾고 API·PostgreSQL·Kafka 로그와 trace ID를 연결한다.
- 종료 기준: 5분과 1시간 error ratio가 모두 임계값 아래로 내려가고 핵심 API smoke가 성공한다. 10분 안에 완화되지 않으면 critical incident로 에스컬레이션한다.

## LogiTrackApiErrorBudgetSlowBurn

- 영향: 낮지만 지속적인 5xx가 장기 가용성 목표를 위협한다.
- 즉시 조치: 변경 동결 여부를 판단하고 30분·6시간 오류율 및 실패 URI를 비교한다.
- 진단: 시간대별 트래픽 구성, 의존 서비스 오류, 반복 background job과 배포 전후 차이를 확인한다.
- 종료 기준: 두 창이 임계값 아래로 안정화되고 원인과 후속 수정이 사건 기록에 남는다. 한 시간 이상 지속되면 담당자에게 에스컬레이션한다.

## LogiTrackApiDown

- 영향: API 또는 metrics 경로가 응답하지 않아 서비스와 관측이 동시에 중단될 수 있다.
- 즉시 조치: 외부 health, 컨테이너 상태, 호스트 자원, 최근 재시작을 확인한다. 프로세스만 실패했다면 원인을 보존한 뒤 재시작한다.
- 진단: API 시작 로그, OOM·disk pressure, PostgreSQL·Kafka 연결 및 Prometheus 네트워크를 확인한다.
- 종료 기준: health와 scrape가 연속 성공하고 핵심 주문 조회가 정상이다. 5분 안에 복구되지 않으면 critical incident로 에스컬레이션한다.

## LogiTrackRecoveryMetricRefreshFailing

- 영향: outbox와 DLQ 상태가 오래되어 실제 복구 backlog를 숨길 수 있다.
- 즉시 조치: API health와 PostgreSQL 연결을 확인하고 recovery metric refresh 예외를 수집한다.
- 진단: DB timeout, pool 고갈, schema drift와 장기 query를 확인한다.
- 종료 기준: refresh failure 증가가 멈추고 backlog gauge가 다시 갱신된다.

## LogiTrackOutboxFailed

- 영향: 재시도를 소진한 도메인 이벤트가 발행되지 않아 DB와 downstream 상태가 불일치할 수 있다.
- 즉시 조치: 실패 행의 aggregate, 마지막 오류와 재시도 횟수를 보존하고 관련 업무 흐름을 식별한다.
- 진단: Kafka availability, serialization, payload 계약과 publisher 로그를 trace ID로 확인한다.
- 종료 기준: 원인을 수정한 뒤 승인된 recovery 절차로 재처리하고 failed 수가 0이며 downstream 반영을 확인한다. 행을 직접 삭제하지 않는다.

## LogiTrackOutboxPublisherFailing

- 영향: 새 이벤트 발행이 지연되고 backlog로 전이될 수 있다.
- 즉시 조치: Kafka health, API publisher 로그와 pending 건수 추이를 확인한다.
- 진단: broker 연결, 인증, topic, serialization 및 DB lock을 확인한다.
- 종료 기준: publish failure 증가가 멈추고 pending backlog가 감소한다.

## LogiTrackOutboxBacklogGrowing

- 영향: 이벤트 반영 지연이 증가하며 장기적으로 DB/event 불일치가 사용자에게 노출된다.
- 즉시 조치: publisher가 살아 있는지와 oldest age를 확인하고 대량 입력 또는 broker 저하 여부를 판단한다.
- 진단: 생성률과 발행률, retry 분포, Kafka latency와 DB polling 시간을 비교한다.
- 종료 기준: backlog와 oldest age가 지속 감소한다. 증가가 15분 이상 이어지면 담당자에게 에스컬레이션한다.

## LogiTrackOutboxOldestPending

- 영향: 최소 한 이벤트가 5분 이상 발행되지 않았다.
- 즉시 조치: 가장 오래된 행의 상태·오류·aggregate를 확인하고 publisher health를 점검한다.
- 진단: 특정 poison payload인지 전체 처리량 문제인지 구분한다.
- 종료 기준: 해당 이벤트가 발행 또는 명시적으로 failed 처리되고 oldest age가 임계값 아래다.

## LogiTrackDeadLetterBacklog

- 영향: telemetry 이벤트가 정상 소비되지 않아 차량 위치 또는 상태가 누락될 수 있다.
- 즉시 조치: DLQ 항목을 폐기하지 말고 오류 유형, schema version, delivery와 vehicle 식별자를 확인한다.
- 진단: payload 계약, 시각 skew, 좌표 범위, consumer 예외를 확인한다.
- 종료 기준: 원인을 수정하고 감사 가능한 replay를 수행해 backlog가 0이며 최신 위치가 반영된다.

## LogiTrackRouteAnalysisDegraded

- 영향: 도로망 분석 대신 local fallback이 반복되어 ETA와 경로 정확도가 낮아질 수 있다.
- 즉시 조치: analytics health와 네트워크를 확인하고 fallback 비율을 기록한다.
- 진단: analytics timeout, 입력 좌표, 외부 도로 데이터 및 API 로그를 확인한다.
- 종료 기준: 정상 분석 outcome이 회복되고 fallback 증가가 멈춘다.

## LogiTrackPdfRenderingFailing

- 영향: KPI PDF 내보내기가 반복 실패한다. 운영 API 자체는 계속 제공될 수 있다.
- 즉시 조치: 동일 기간의 CSV export와 KPI 조회가 되는지 확인해 우회 경로를 제공한다.
- 진단: renderer 응답, template 데이터, timeout, memory와 특수문자 입력을 확인한다.
- 종료 기준: 대표 보고서 PDF가 생성되고 failure counter 증가가 멈춘다.

## LogiTrackKpiProjectionStale

- 영향: 일별 KPI가 최신 운영 상태를 반영하지 않는다.
- 즉시 조치: 마지막 성공 시각, refresh interval, projection job 로그와 PostgreSQL health를 확인한다.
- 진단: scheduler 정지, transaction 실패, lock과 계산 query 시간을 확인한다.
- 종료 기준: projection 성공 시각이 갱신되고 조회 결과가 원천 데이터와 일치한다.

## LogiTrackApiServerErrors

- 영향: 최근 5분에 반복 5xx가 발생했다.
- 즉시 조치: 실패 URI, status, trace ID와 배포 시점을 수집한다.
- 진단: 애플리케이션 예외와 의존 서비스 timeout을 구분하고 같은 입력으로 재현한다.
- 종료 기준: 원인 경로 smoke가 성공하고 5xx 증가가 멈춘다. SLO burn 경보와 함께 발생하면 해당 경보 절차를 우선한다.

## LogiTrackApiLatencyHigh

- 영향: p95가 2초를 넘어 관제 화면과 API 사용자 경험이 저하된다.
- 즉시 조치: 요청률, 느린 URI, JVM·DB·호스트 자원과 consumer lag를 확인한다.
- 진단: trace에서 병목 span을 찾고 DB slow query, pool, GC와 downstream timeout을 확인한다.
- 종료 기준: 정상 부하에서 p95가 2초 아래로 10분 이상 유지된다.

## LogiTrackTelemetryConsumerLagHigh

- 영향: 차량 위치 반영이 늦어져 실시간 관제가 오래된 정보를 표시한다.
- 즉시 조치: consumer assignment, broker health, 입력률과 처리율을 확인한다.
- 진단: poison event retry, partition 편중, DB latency와 consumer 재시작을 확인한다.
- 종료 기준: lag가 지속 감소해 100 아래이며 위치 반영 지연이 목표 범위로 돌아온다.

## LogiTrackTelemetryConsumerMissing

- 영향: telemetry consumer가 partition을 할당받지 못해 위치 갱신이 중단됐을 수 있다.
- 즉시 조치: API와 Kafka 상태, consumer group assignment, 최근 rebalance 로그를 확인한다.
- 진단: topic 존재, group 설정, broker 연결과 consumer thread 예외를 확인한다.
- 종료 기준: assigned partition metric이 복구되고 새 telemetry가 위치에 반영된다. 5분 안에 복구되지 않으면 critical incident로 에스컬레이션한다.

## LogiTrackRetentionCleanupFailing

- 영향: 운영 데이터 보존 정책이 실행되지 않아 DB 사용량과 개인정보 최소화 경계가 악화된다.
- 즉시 조치: 디스크 여유, 마지막 cleanup 결과와 transaction 오류를 확인한다.
- 진단: FK·lock·timeout, batch 크기와 대상 행 수를 확인한다.
- 종료 기준: cleanup이 성공하고 삭제량 metric이 갱신된다. 임의 SQL 대량 삭제는 금지한다.

## LogiTrackDemoCleanupFailing

- 영향: 완료된 demo 배송이 쌓여 공개 showcase의 품질과 DB 사용량이 저하된다.
- 즉시 조치: monitor 시작·마지막 성공 시각, 실패 counter와 API scheduler 로그를 확인한다.
- 진단: cleanup transaction, lock, demo 식별 규칙과 DB 연결을 확인한다.
- 종료 기준: cleanup 성공 시각이 갱신되고 완료 demo 항목이 정책 범위로 감소한다.

## LogiTrackDemoFleetBelowTarget

- 영향: 공개 showcase에 표시되는 이동 차량 수가 목표보다 작다.
- 즉시 조치: simulator, API, Kafka와 replenishment failure를 확인한다.
- 진단: 생성 제한, demo cleanup과 replenishment 경쟁, 주문·배차 오류 및 simulator publish를 확인한다.
- 종료 기준: 활성 demo 배송이 목표에 도달하고 replenishment failure 증가가 멈춘다.

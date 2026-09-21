# ADR 0006: PostgreSQL 일별 배송 KPI projection

## 상태

채택됨 — 2026-09-19

## 결정

- 배송 생성일을 UTC 일자 cohort로 삼아 공개 API의 최대 범위인 최근 90일을 `delivery_daily_kpis`에 projection한다.
- 애플리케이션 시작 러너가 트래픽 수락 전에 projection 전체를 초기화하고, Spring scheduler가 이후 60초마다 갱신한다. 보고서 GET은 projection을 읽기만 한다. 브라우저 수에 비례하는 중복 UPSERT, 읽기 요청의 부작용, 재시작 직후의 부분 결과를 피하면서 최대 60초의 명시적인 최신성 경계를 둔다.
- PostgreSQL `generate_series`, filtered aggregate, `ON CONFLICT` upsert를 사용해 배송이 없는 날짜도 0으로 유지한다.
- 정시 도착률은 최초 불변 route snapshot의 `planned_eta`와 배송 완료 시각을 비교한다.
- JSON API는 대시보드에, UTF-8 CSV API는 운영 보고서 다운로드에 사용한다.

## 이유

원본 배송 테이블을 브라우저가 직접 집계하지 않으므로 지표 정의가 한 곳에 고정되고, 보고서 요청 비용과 응답 형태가 예측 가능하다. UTC cohort는 서버·브라우저의 시간대가 달라도 같은 일자 결과를 제공한다.

## 한계와 후속

- 현재 `updated_at`을 완료 시각으로 사용한다. 별도 상태 이력 테이블이 추가되면 명시적 `delivered_at`으로 전환한다.
- 최초 planned ETA가 없는 완료 배송은 정시 도착률 분모에서 제외한다.
- 월별 대용량 범위가 필요해지면 이벤트 기반 증분 projection과 보존 정책을 추가한다.

# ADR 0008: 선택 범위 replay의 승인과 속도 제한

## 상태

채택됨 — 2026-09-19

## 결정

- 운영자는 최대 20개의 `PENDING` DLQ event ID로 10분 유효한 `PREPARED` replay plan을 먼저 만든다.
- plan 생성은 payload를 발행하지 않는 dry-run이며 대상 존재 여부, 중복 ID, 상태, 운영자 식별자를 검증한다.
- 실행은 같은 `X-Operator`와 명시적 `X-Replay-Approval: APPROVE` 헤더를 요구한다.
- PostgreSQL pessimistic lock과 plan 상태 전이가 같은 plan의 동시·중복 실행을 막는다.
- 기본 5 events/s로 순차 발행하고 기존 단일 replay 감사 행을 이벤트별로 남긴다. 최대 크기와 속도는 설정으로 조정한다.
- 일부 발행이 실패하면 plan은 `PARTIAL`, 모두 성공하면 `EXECUTED`, 만료 시 `EXPIRED`가 된다.

## 이유

대량 replay는 정상 consumer를 다시 압박하거나 poison event 폭주를 만들 수 있다. 검토 가능한 dry-run, 짧은 승인 창, 명시적 실행 의사, 작은 batch와 속도 제한을 결합해 blast radius를 제한한다.

## 트레이드오프

현재 실행 요청은 최대 약 4초 동안 동기적으로 완료를 기다린다. 더 큰 범위가 필요하면 동일 plan 모델을 비동기 worker로 옮기되 승인·감사·rate limit 규칙은 유지한다.


# ADR 0004: 상태 기반 배송 경고 lifecycle

상태: 채택 (2026-09-19)

## 결정

Telemetry를 저장하는 같은 트랜잭션에서 최신 route snapshot과 비교해 경고를 평가한다. 경고 유형은 `DELAY`, `ROUTE_DEVIATION`, 상태는 `ACTIVE`, `RESOLVED`, 심각도는 `WARNING`, `CRITICAL`로 시작한다.

- 경로 이탈: 계획 polyline과 현재 위치의 최소 거리 500m 이상에서 발생, 300m 이하에서 해결, 1.5km 이상이면 critical
- 지연: telemetry ETA가 계획 ETA보다 10분 이상 늦거나 상태가 `DELAYED`이면 발생, 5분 이하에서 해결, 30분 이상이면 critical
- 활성 경고는 배송·유형별 하나이며 반복 관측은 횟수와 최종 관측값만 갱신한다.
- 활성 상태의 심각도는 낮추지 않고 해결 후 새 경고가 발생할 때 다시 계산한다.
- 발생, 심각도 상승, 해결만 transactional outbox의 `delivery.alert.v1`으로 발행한다.

## 이유

발생과 해결 임계값을 다르게 두면 GPS 오차나 경계값 진동으로 경고가 반복 생성되는 것을 막는다. 활성 경고 유일성과 outbox를 함께 사용하면 at-least-once telemetry 환경에서도 운영자에게 중복 경고를 보내지 않으면서 상태 전이를 유실하지 않는다.

## 후속 확장

차량·화물·운송 계약별 threshold, 운영자 확인 상태, 알림 채널 routing과 평가 규칙 버전 관리를 추가할 수 있다.


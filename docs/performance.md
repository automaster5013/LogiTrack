# 로컬 성능 기준선

측정일: 2026-09-19

## 배송 생성 API

로컬 Docker Compose 환경에서 멱등 재시도 workload를 초당 20건, 15초 동안 실행했다.

| 항목 | 결과 | 기준 |
|---|---:|---:|
| 요청 | 300 | 300 |
| 달성 처리량 | 20.04 RPS | 20 RPS |
| 성공률 | 100.0% | 99% 이상 |
| 평균 latency | 19.24 ms | 참고 |
| p95 latency | 35.63 ms | 500 ms 이하 |
| p99 latency | 41.76 ms | 참고 |
| 최대 latency | 48.17 ms | 참고 |

명령은 `./scripts/load-smoke.ps1`이다. 기본 시나리오는 같은 멱등 키의 재시도이므로 운영 클라이언트 retry 경로와 DB lookup 비용을 측정하며 테스트 데이터는 한 건만 생성한다. 모든 요청이 새 배송을 생성하는 write-heavy 시험은 `python ./load/delivery_load.py --rate 20 --duration 15 --unique`로 별도 실행할 수 있다.

도로 경로 분석은 동일 좌표를 5분간 최대 1,024건 캐시해 공개 OSRM 호출을 억제한다. 이는 외부 provider latency와 rate limit가 로컬 API 기준선을 왜곡하는 것을 줄이며, 서로 다른 좌표의 경로는 독립적으로 계산한다.

## 해석과 한계

- 이 결과는 단일 API 인스턴스의 로컬 기준선이며 운영 용량 보장을 의미하지 않는다.
- 고유 생성 workload, Kafka consumer lag, telemetry 반영 지연은 다음 성능 단계에서 별도 측정한다.
- 측정 전후 컨테이너 health와 API 오류 로그를 확인한다.


# 테스트 품질 기준선

측정일: 2026-09-19

## 도메인 coverage gate

JaCoCo가 핵심 상태 전이와 불변식을 소유한 도메인 클래스의 line 및 branch coverage를 각각 80% 이상으로 강제한다. Controller, repository, 설정, 외부 시스템 adapter는 이 지표에 섞지 않고 통합 smoke test에서 별도로 검증한다.

포함 클래스:

- `Delivery`, `CustomerOrder`, `WarehouseStock`
- `DeliveryAlert`, `RouteDeviationCalculator`
- `DeadLetterEvent`, `ReplayPlan`

| 항목 | 결과 | 실패 기준 |
|---|---:|---:|
| Line coverage | 90.38% (94/104) | 80% 미만 |
| Branch coverage | 96.88% (31/32) | 80% 미만 |

`./scripts/domain-coverage.ps1`은 고정된 Maven/JDK 21 컨테이너에서 전체 API 테스트와 JaCoCo 검사를 실행한다. 기준을 충족하지 못하면 `mvn verify`와 스크립트가 모두 실패하므로 회귀를 커밋 전에 차단할 수 있다. HTML 상세 보고서는 실행 후 `api/target/site/jacoco/index.html`에 생성된다.

## 보완 검증

- Python analytics의 경로 계산과 PDF 생성은 `analytics/tests`에서 검증한다.
- TypeScript 프론트엔드는 production build의 type check로 검증한다.
- PostgreSQL, Kafka, Redis, SSE, 지도와 전체 이벤트 흐름은 각 `scripts/*-smoke.ps1` 및 실제 브라우저 검증으로 확인한다.

## 지속적 통합

`.github/workflows/ci.yml`은 `main` push와 모든 pull request에서 세 개의 독립 job을 병렬 실행한다.

- Java 21 API 테스트와 JaCoCo domain coverage gate
- Python 3.12 analytics/simulator 테스트와 Compose topology 검증
- Node.js 22 TypeScript production build

외부 배포나 secret은 사용하지 않으며 `GITHUB_TOKEN` 권한은 `contents: read`로 제한한다. 같은 branch에 새 실행이 시작되면 이전 실행을 취소해 불필요한 runner 사용도 줄인다.

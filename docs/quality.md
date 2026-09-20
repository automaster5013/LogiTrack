# 테스트 품질 기준선

측정일: 2026-09-19

## 도메인 coverage gate

JaCoCo가 핵심 상태 전이와 불변식을 소유한 도메인 클래스의 line 및 branch coverage를 각각 80% 이상으로 강제한다. Controller, repository, 설정, 외부 시스템 adapter는 이 지표에 섞지 않고 통합 smoke test에서 별도로 검증한다.

포함 클래스:

- `Delivery`, `CustomerOrder`, `WarehouseStock`
- `DeliveryAlert`, `AlertPolicy`, `RouteDeviationCalculator`
- `DeadLetterEvent`, `ReplayPlan`

| 항목 | 결과 | 실패 기준 |
|---|---:|---:|
| Line coverage | 92.37% (121/131) | 80% 미만 |
| Branch coverage | 88.71% (55/62) | 80% 미만 |

`./scripts/domain-coverage.ps1`은 고정된 Maven/JDK 21 컨테이너에서 전체 API 테스트와 JaCoCo 검사를 실행한다. 기준을 충족하지 못하면 `mvn verify`와 스크립트가 모두 실패하므로 회귀를 커밋 전에 차단할 수 있다. HTML 상세 보고서는 실행 후 `api/target/site/jacoco/index.html`에 생성된다.

## 보완 검증

- Python analytics의 경로 계산과 PDF 생성은 `analytics/tests`에서 검증한다.
- TypeScript 프론트엔드는 production build의 type check로 검증한다.
- PostgreSQL, Kafka, Redis, SSE, 지도와 전체 이벤트 흐름은 각 `scripts/*-smoke.ps1` 및 실제 브라우저 검증으로 확인한다.

## 지속적 통합

`.github/workflows/ci.yml`은 `main` push와 모든 pull request에서 세 개의 독립 job을 병렬 실행한다.

모든 job은 `ubuntu-24.04` runner에 고정해 `ubuntu-latest`의 예고 없는 OS 전환을 피한다. `scripts/workflow-config-smoke.py`는 runner 고정, action commit SHA, job timeout, 최소 token 권한을 CI 안에서 회귀 검증한다.

CI의 Prometheus 검증과 로컬 domain coverage에 쓰는 도구 컨테이너도 production image와 같은 방식으로 SHA-256 digest에 고정한다. Compose 구성 smoke가 이 두 직접 실행 경로의 가변 태그 재도입도 차단한다.

- Java 21 API 테스트와 JaCoCo domain coverage gate
- Python 3.12 analytics/simulator 테스트와 Compose topology 검증
- Node.js 22 TypeScript production build
- API, analytics, simulator, web production image build와 non-root runtime 검사
- 자체 이미지 5종의 standalone runtime에서도 유지되는 image-native healthcheck 검사
- digest로 고정한 Trivy를 통한 CycloneDX SBOM artifact 생성과 CRITICAL 취약점 0건 gate
- digest로 고정한 Trivy offline secret scan을 통한 커밋 비밀정보 0건 gate

외부 배포나 secret은 사용하지 않으며 `GITHUB_TOKEN` 권한은 `contents: read`로 제한한다. 같은 branch에 새 실행이 시작되면 이전 실행을 취소해 불필요한 runner 사용도 줄인다.

PostgreSQL backup/restore 스크립트는 CI에서 digest 고정 PostgreSQL 컨테이너와 임시 volume을 기동해 실제 custom-format dump를 격리 DB에 복원한다. 성공 여부와 관계없이 `docker compose down --volumes --remove-orphans`를 실행해 runner의 데이터와 컨테이너를 제거한다.

SBOM artifact는 commit SHA가 포함된 이름으로 30일 보관한다. 로컬에서는 production image를 `./scripts/container-build.ps1`로 만든 다음 `./scripts/container-security.ps1`로 같은 정책을 재현한다.

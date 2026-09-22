# CI/CD와 릴리스 전략

## 현재 상태

- CI는 구현되어 있다. GitHub Actions가 API 테스트와 coverage, Python 테스트, Compose 구성, PostgreSQL backup/restore 왕복, Prometheus alert rule 문법, TypeScript build를 검증한다.
- production Docker image 다섯 개도 clean runner에서 빌드하고 모든 runtime이 non-root인지 검사한다.
- 각 image의 CycloneDX SBOM을 30일 보관하고, 수정 가능 여부와 관계없이 CRITICAL 취약점이 하나라도 있으면 CI를 차단한다.
- CD 1단계로 수동 승인된 staging image publication을 구현했다. `.github/workflows/publish-staging-images.yml`은 `main`에 포함된 full commit SHA만 받아 GitHub `staging` environment 승인 뒤 OIDC 단기 자격 증명으로 검증 완료 이미지를 ECR에 게시한다.
- ECS/RDS/ElastiCache/MSK/ALB/Route 53 등 runtime 인프라 생성과 서비스 배포는 아직 구현하지 않았다. 리전·비용 상한·복구 정책이 확정되기 전에는 AWS runtime 자원을 변경하지 않는다.

## CD를 시작할 시점

현재 코드 품질과 컨테이너 재현성이 갖춰졌으므로 스테이징 CD 설계를 시작하기 좋은 상태다. 실제 자동 배포는 아래 조건을 먼저 확정한 뒤 시작한다.

1. 배포 대상과 소유 계정, 리전 또는 호스팅 위치 (`logitrack.kr`은 구매 완료된 운영 도메인)
2. 월 비용 상한과 자동 중지·삭제 정책
3. 비밀정보 저장소와 접근 권한 책임자
4. PostgreSQL backup/restore 및 migration rollback 절차
5. 지도 style/tile provider의 운영 quota, CORS, 장애 fallback 정책
6. 스테이징 health/smoke 기준과 운영 승인을 담당할 사람

## 권장 파이프라인

```text
pull request
  → CI tests / coverage / TypeScript build
  → immutable container build / SBOM / vulnerability scan
  → registry push (commit SHA tag)
  → staging deploy
  → readiness + order/delivery/map smoke
  → manual production approval
  → rolling deploy
  → post-deploy smoke
  → 실패 시 이전 image + DB 호환 migration으로 rollback
```

## Staging image publication 준비

GitHub repository의 `staging` environment에 승인자를 지정하고 아래 environment variable을 설정한다.

- `AWS_ROLE_ARN`: 이 저장소와 `staging` environment에서만 assume할 수 있는 GitHub OIDC IAM role
- `AWS_REGION`: ECR repository가 위치한 확정 리전
- `AWS_ACCOUNT_ID`: 게시가 허용된 AWS 계정의 12자리 ID
- `ECR_REPOSITORY_PREFIX`: 사전에 생성한 repository prefix(예: `logitrack`)

ECR에는 `<prefix>/api`, `<prefix>/analytics`, `<prefix>/simulator`, `<prefix>/web`, `<prefix>/otel-collector` repository가 먼저 존재해야 한다. workflow는 OIDC 자격 증명이 `AWS_ACCOUNT_ID`와 정확히 일치하는지 먼저 확인하며, 계정이 다르거나 변수가 없으면 ECR 접근 전에 실패한다. 각 repository가 immutable tag, scan-on-push, AES256 encryption과 검증된 2개 lifecycle rule을 실제로 사용하는지도 build 전에 조회한다. 미태그 image 1~30일 만료와 최신 image 10~200개 보존 범위를 벗어나거나 추가 만료 rule이 있으면 drift로 판단해 게시를 차단한다. repository나 다른 AWS 자원을 생성하지 않으며, 하나라도 없으면 build 전에 실패한다. 장기 access key와 AWS 로그인 이메일은 GitHub secret·variable·소스 코드에 저장하지 않는다.

`infra/aws/bootstrap` Terraform root는 이 사전 구성을 재현한다. 기존 GitHub Actions OIDC provider ARN과 확정 리전만 입력받아 immutable tag·scan-on-push·Terraform destroy 차단·비어 있지 않으면 AWS 삭제 불가인 ECR repository 5개와 해당 repository에만 push 가능한 IAM role을 정의한다. OIDC provider ARN의 계정 ID가 Terraform caller 계정과 다르면 plan 단계에서 차단해 잘못된 AWS 계정에 trust를 구성하지 못하게 한다. 각 repository는 기본적으로 rollback용 최신 image 30개를 유지하고 tag가 없는 image는 7일 뒤 만료해 저장 비용이 무한히 증가하지 않도록 한다. 보존 개수(10~200)와 미태그 유예 기간(1~30일)은 검증된 Terraform 입력으로만 조정한다. role trust는 `automaster5013/LogiTrack`의 `staging` environment subject로 제한한다. Terraform state backend와 비용 상한을 확정한 뒤 plan을 사람이 검토하기 전에는 apply하지 않는다.

`Publish staging images` workflow를 수동 실행하면서 `main`에 포함된 40자리 commit SHA를 전달한다. workflow는 이미지 5종의 non-root/healthcheck, CycloneDX SBOM provenance, CRITICAL 취약점 0건을 다시 확인한 뒤에만 `<ECR registry>/<prefix>/<service>:<commit SHA>`로 push한다. 일부 image만 게시된 뒤 실행이 중단되어도 재실행할 수 있다. publisher role은 이 재검증에 필요한 image manifest와 layer만 다섯 LogiTrack repository에서 읽을 수 있다. 이미 존재하는 immutable tag는 ECR digest 형식과 내려받은 image의 OCI revision label이 요청 SHA와 일치할 때만 재사용하며, tag 충돌이나 provenance 불일치는 즉시 실패한다. 이어서 ECR에서 각 digest를 다시 조회해 계정·리전·revision, source repository, GitHub workflow run ID·attempt와 digest 고정 URI 5개를 담은 `staging-release-manifest-<commit SHA>` artifact를 30일 보관한다. standalone manifest만 전달되어도 어느 실행이 게시했는지 추적할 수 있다. 이후 배포 단계는 tag 대신 이 manifest의 digest URI를 사용한다. `latest` tag는 만들지 않는다.

현재 단계는 배포 가능한 artifact publication까지다. 실제 staging 서비스 전환은 runtime topology, 월 비용 상한, DB migration/rollback, TLS와 `logitrack.kr` DNS 정책 승인 후 별도 단계로 추가한다.

운영 배포에서는 `latest` tag를 사용하지 않고 Git commit SHA로 image를 고정한다. 애플리케이션 migration은 이전 버전과 호환되는 expand/contract 순서를 사용하며, 배포 성공 판정에는 API readiness뿐 아니라 주문 생성·배차·지도 경로 조회까지 포함한다.

로컬 빌드도 Dockerfile 기반 이미지와 Compose 외부 이미지를 `tag@sha256:digest`로 고정한다. 버전 갱신은 새 digest로 명시적으로 교체하고 CI의 전체 테스트·SBOM·취약점 검사를 함께 통과해야 한다.

Dependabot은 매주 GitHub Actions, Maven, npm, Python, Dockerfile, Docker Compose 의존성을 확인한다. minor/patch 갱신은 생태계별 단일 PR로 묶고 major 갱신은 독립 PR로 남겨 영향 범위를 명확히 하며, 고정된 컨테이너 tag의 새 digest도 같은 CI 게이트를 통과해야 한다.

각 production image build context는 `.dockerignore`로 `.env*`, 로컬 build/cache, test artifact를 제외한다. OpenTelemetry Collector context는 Dockerfile만 허용하며 CI가 필수 제외 규칙의 누락을 차단한다.

## 로컬 릴리스 검증

`./scripts/container-build.ps1`은 API, analytics, simulator, web, OpenTelemetry Collector production image를 현재 commit SHA label과 함께 빌드하고 root runtime을 거부한다. 이어서 `./scripts/container-security.ps1`을 실행하면 digest로 고정한 Trivy 0.74.0이 `work/sbom/*.cdx.json`을 만들고 다섯 image의 CRITICAL 취약점 0건을 강제한다. 실제 registry push나 배포는 수행하지 않는다.

SBOM은 업로드 전에 `scripts/sbom-smoke.py`로 검증한다. 정확히 다섯 서비스의 CycloneDX 1.7 문서인지, 각 문서의 container image tag·SHA-256 image ID·구성요소 reference·OCI revision label이 현재 commit과 일치하는지 확인하며, 하나라도 불일치하면 artifact 게시를 차단한다.

API는 Spring Boot 3.4.13을 사용하며, 2026년 공개 취약점이 수정된 정식 릴리스 Tomcat 10.1.60과 Netty 4.1.137.Final을 명시적으로 고정한다. 프레임워크의 기본 관리 버전으로 되돌릴 때도 image scan이 통과해야 한다.

웹 production runtime에는 `node` 실행 파일과 standalone 산출물만 남기고, 빌드 단계에서만 필요한 npm, Corepack, Yarn은 제거한다. 패키지 설치와 TypeScript/Next.js build는 앞선 격리 stage에서 계속 잠금 파일을 기준으로 수행한다.

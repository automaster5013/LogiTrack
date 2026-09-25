# CI/CD와 릴리스 전략

## 현재 상태

- CI는 구현되어 있다. GitHub Actions가 API 테스트와 coverage, Python 테스트, Compose 구성, PostgreSQL backup/restore 왕복, Prometheus alert rule 문법, TypeScript build를 검증한다.
- production Docker image 다섯 개도 clean runner에서 빌드하고 모든 runtime이 non-root인지 검사한다.
- 각 image의 CycloneDX SBOM을 30일 보관하고, 수정 가능 여부와 관계없이 CRITICAL 취약점이 하나라도 있으면 CI를 차단한다.
- 수동 승인된 staging image publication을 구현했다. `.github/workflows/publish-staging-images.yml`은 `main`에 포함된 full commit SHA만 받아 GitHub `staging` environment 승인 뒤 OIDC 단기 자격 증명으로 검증 완료 이미지를 ECR에 게시한다.
- Docker Hub continuous delivery도 구현했다. `main` push의 전체 CI가 성공한 경우에만 `.github/workflows/publish-dockerhub-images.yml`이 `automaster5013/logitrack-{api,analytics,simulator,web,otel-collector}:<full commit SHA>`를 자동 게시한다. 이미지는 push 전에 SBOM과 CRITICAL 취약점 검사를 통과하고, push 뒤 registry digest로 다시 pull해 platform과 OCI provenance를 검증한다.
- 저비용 staging runtime과 실제 배포 단계도 구현했다. 서울 리전의 단일 EC2, 암호화 gp3, Elastic IP, Route 53, Caddy TLS, SSM 배포와 USD 70 Budget을 사용하며 NAT Gateway, ALB, RDS, ElastiCache, MSK와 SSH ingress는 만들지 않는다.
- `.github/workflows/deploy-staging.yml`은 게시 실행의 release manifest와 ECR digest를 재검증하고 OIDC 단기 자격 증명으로 지정 instance에만 SSM 명령을 보낸다. Compose health와 외부 HTTPS/HSTS가 모두 통과해야 배포가 성공한다.
- `.github/workflows/staging-health.yml`은 별도 cloud 자격 증명 없이 6시간마다 DNS, HTTP→HTTPS redirect, LogiTrack 로그인 화면 식별자, 공개 origin으로만 복귀하는 잘못된 OIDC callback과 임시 쿠키 제거, 인증 프록시의 cross-origin 변경 거부와 비로그인 읽기·쓰기 거부 응답의 JSON·`no-store`·쿠키 비변경, 알려진 인증 실패의 안전한 안내와 알 수 없는 오류 비노출, cache 금지된 runtime UUID endpoint, TLS 인증서의 14일 이상 잔여기간, CSP를 포함한 보안 header, 서버·reverse proxy·프레임워크 식별 header와 내부 서비스 포트 비노출을 검사한다.
- staging 배포도 완료 처리 전에 로그인 시작 응답의 Cognito authorize 대상·PKCE challenge·state·nonce·5분 Secure/HttpOnly 쿠키 결합, 잘못된 callback의 공개 로그인 URL 복귀·임시 쿠키 제거·access token 비변경, logout의 same-origin 강제·Cognito 공개 복귀 URL·전체 인증 쿠키 제거, 인증 프록시의 cross-origin·비로그인 요청 거부와 cache·쿠키 경계, 알려진 인증 실패 안내·재시도·접근성 경고, 오류 응답의 `no-store`와 쿠키 비변경, 알 수 없는 오류 비노출을 검사한다.

## 현재 staging CD 경계

Docker Hub CD는 GitHub repository secret `DOCKERHUB_TOKEN` 하나만 사용한다. 이 값에는 Docker Hub의 repository Read/Write 권한만 부여하고 Delete 권한은 부여하지 않는다. 계정명과 대상 namespace는 `automaster5013`으로 workflow에 고정되어 있어 다른 namespace로의 우발적 게시를 막는다. Docker Hub에는 mutable `latest`를 만들지 않으며, 재실행 시 기존 commit tag의 실제 image ID가 새 빌드와 다르면 overwrite 대신 실패한다.

staging CD는 서울 리전의 `www.logitrack.kr`에 적용되어 있다. image 게시와 runtime 배포는 분리된 수동 workflow이며 둘 다 GitHub `staging` environment의 승인과 AWS OIDC 단기 자격 증명을 요구한다. 장기 AWS access key나 AWS 로그인 계정은 GitHub에 저장하지 않는다.

GitHub 저장소의 실제 승인자·`main` 전용 deployment branch·environment 변수·secret 부재·기본 token read 권한과 action SHA 고정 설정은 `./scripts/github-cd-boundary-audit.ps1`로 읽기 전용 감사한다.

GitHub의 Dependabot vulnerability alerts와 security update PR, secret scanning과 push protection을 활성화한다. 같은 감사 스크립트는 설정 drift뿐 아니라 미해결 secret 경고와 high·critical Dependabot 경고가 없는지도 확인한다.

공개 저장소의 private vulnerability reporting을 활성화하고 루트 `SECURITY.md`에서 공개 issue 대신 Security advisories의 비공개 신고 경로를 안내한다. 감사 스크립트는 이 신고 채널이 비활성화된 상태도 drift로 차단한다.

CodeQL default setup은 Actions, Java/Kotlin, JavaScript/TypeScript와 Python을 표준 runner에서 매주 extended query suite로 분석한다. threat model은 원격 입력으로 제한하고, 감사 스크립트는 설정 drift와 미해결 high·critical CodeQL 경고를 차단한다.

OpenSSF Scorecard는 `main` push와 주간 일정에서 저장소의 공급망 보안 상태를 분석한다. workflow 기본 권한은 read-only이며 SARIF 게시와 공개 결과 증명에 필요한 `security-events: write`, `id-token: write`만 분석 job에 부여한다. 결과 SARIF는 30일 보존하고 GitHub code scanning에도 게시한다. PR 코드는 이 쓰기 권한 workflow에서 실행하지 않는다.

`main` branch는 관리자에게도 동일하게 적용되는 PR 경로, 최신 branch 기준 필수 CI 4개, 선형 이력과 대화 해결을 요구하며 force push와 삭제를 금지한다. 1인 유지보수를 막지 않도록 별도 승인 수는 0이지만 stale review는 새 push 때 무효화한다. 저장소는 squash merge만 허용하고 merge 후 source branch를 자동 삭제한다.

현재 운영 경계는 다음과 같다.

1. 월 비용 상한은 USD 70 Budget이며 80% 실제 비용과 100% forecast를 직접 email로 알린다. Budget은 리소스를 자동 중지하는 hard cap이 아니다.
2. 비밀정보는 SSM SecureString에 저장하고 배포 시 대상 EC2에서만 읽는다.
3. image는 commit SHA와 digest로 고정하고 검증된 release manifest 없이는 배포하지 않는다.
4. 배포 실패 시 직전 release로 자동 rollback하며 database schema는 expand/contract 호환성을 유지한다.
5. root EBS는 매일 snapshot하고 PostgreSQL custom dump는 별도 비공개 S3 bucket에 매일 저장한다.
6. EC2 system status failure는 CloudWatch alarm이 자동 복구하고, 외부 health workflow는 6시간마다 공개 경계와 내부 포트 비노출을 검사한다.

이 구성은 비용을 우선한 단일 호스트 staging이다. production 전환 전에는 다중 AZ 데이터 계층, point-in-time recovery, 무중단 migration, 알림 수신 책임자, 지도 공급자 SLA와 별도 비용 승인을 확정해야 한다.

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

ECR에는 `<prefix>/api`, `<prefix>/analytics`, `<prefix>/simulator`, `<prefix>/web`, `<prefix>/otel-collector` repository가 먼저 존재해야 한다. workflow는 runner에 남은 AWS 자격 증명을 먼저 제거하고 환경 변수의 암묵적 action input 변환을 차단해 명시된 OIDC 설정만 사용한다. OIDC 자격 증명 action의 허용 계정을 `AWS_ACCOUNT_ID`로 제한하고 계정 ID를 log에서 마스킹한 뒤, STS 결과도 같은 값과 다시 대조한다. 역할 인수는 최대 5회, 전체 120초로 제한해 장애나 오구성에서 무한정 대기하지 않는다. ECR login이 반환한 registry도 승인 계정·리전으로 계산한 endpoint와 일치해야만 build를 시작한다. 계정이나 registry가 다르거나 변수가 없으면 게시 전에 실패한다. AWS CLI는 `standard` retry mode에서 최대 5회만 재시도해 일시적인 STS·ECR 오류를 흡수하면서도 실패 시간을 제한하고, pager를 비활성화해 CI가 대화형 출력에서 대기하지 않게 한다. 각 repository가 immutable tag, scan-on-push, AES256 encryption과 검증된 2개 lifecycle rule을 실제로 사용하는지도 build 전에 조회한다. 미태그 image 1~30일 만료와 최신 image 10~200개 보존 범위를 벗어나거나 추가 만료 rule이 있으면 drift로 판단해 게시를 차단한다. repository나 다른 AWS 자원을 생성하지 않으며, 하나라도 없으면 build 전에 실패한다. 장기 access key와 AWS 로그인 이메일은 GitHub secret·variable·소스 코드에 저장하지 않는다.

`infra/aws/bootstrap` Terraform root는 이 사전 구성을 재현한다. 기존 GitHub Actions OIDC provider ARN과 확정 리전만 입력받아 immutable tag·scan-on-push·Terraform destroy 차단·비어 있지 않으면 AWS 삭제 불가인 ECR repository 5개와 해당 repository에만 push 가능한 IAM role을 정의한다. OIDC provider ARN의 계정 ID가 Terraform caller 계정과 다르면 plan 단계에서 차단해 잘못된 AWS 계정에 trust를 구성하지 못하게 한다. 각 repository는 기본적으로 rollback용 최신 image 30개를 유지하고 tag가 없는 image는 7일 뒤 만료해 저장 비용이 무한히 증가하지 않도록 한다. 보존 개수(10~200)와 미태그 유예 기간(1~30일)은 검증된 Terraform 입력으로만 조정한다. role trust는 `automaster5013/LogiTrack`의 `staging` environment subject로 제한한다. Terraform state backend와 비용 상한을 확정한 뒤 plan을 사람이 검토하기 전에는 apply하지 않는다.

`Publish staging images` workflow를 수동 실행하면서 `main`에 포함된 40자리 commit SHA를 전달한다. workflow는 이미지 5종의 non-root/healthcheck, OCI revision·source label, CycloneDX SBOM provenance, CRITICAL 취약점 0건을 다시 확인한 뒤에만 `<ECR registry>/<prefix>/<service>:<commit SHA>`로 push한다. 일부 image만 게시된 뒤 실행이 중단되어도 재실행할 수 있다. publisher role은 이 재검증에 필요한 image manifest와 layer만 다섯 LogiTrack repository에서 읽을 수 있다. 이미 존재하는 immutable tag는 ECR에서 먼저 확인한 digest URI로 pull해 tag 조회와 검증 사이의 변경 가능성을 제거하고, OCI revision·source label이 요청 SHA와 이 GitHub repository에 모두 일치할 때만 재사용한다. tag 충돌이나 provenance 불일치는 즉시 실패한다. 이어서 ECR에서 각 digest를 다시 조회해 UTC 게시 시각, 계정·리전·revision, source repository, GitHub workflow run ID·attempt, digest 고정 URI 5개와 각 CycloneDX SBOM 파일명·SHA-256을 담은 `staging-release-manifest-<commit SHA>` artifact를 30일 보관한다. manifest 검증기는 기록된 게시 시각 형식과 SHA-256을 실제 workflow 값·SBOM 파일 내용에 직접 대조한다. `sbomArtifact`는 같은 revision의 SBOM artifact를 지정하고 `sbomArtifactDigest`는 GitHub가 계산한 artifact archive SHA-256을 고정한다. `sbomArtifactUrl`은 source repository와 workflow run ID에 속한 GitHub artifact 주소만 허용하므로 standalone manifest에서 공급망 증적으로 바로 이동하면서 다운로드한 SBOM 묶음의 동일성과 게시 실행을 함께 검증할 수 있다. workflow 실행 요약에는 revision, UTC 게시 시각, 검증된 GitHub artifact 다운로드 링크와 SBOM·release manifest archive digest를 남겨 운영자가 인수할 증적을 바로 내려받고 무결성을 대조할 수 있다. 이후 배포 단계는 tag 대신 이 manifest의 digest URI를 사용한다. `latest` tag는 만들지 않는다.

publisher는 신규 빌드와 기존 ECR image 재사용 모두 Docker image metadata의 OS·architecture가 `linux/amd64`인지 확인한다. release manifest의 `imagePlatform`도 같은 값으로 고정해 이후 runtime 배포가 호환되지 않는 architecture를 암묵적으로 선택하지 못하게 한다. ECR에서 digest별 manifest media type도 다시 조회해 OCI image manifest 또는 Docker distribution v2 manifest만 허용하고, index나 legacy 형식은 배포 증적 생성 전에 거부한다. ECR이 보고한 압축 image 크기도 서비스별로 기록하며 1 byte 미만 또는 2 GiB 초과 image는 저장 비용과 배포 지연을 키우는 비정상 산출물로 간주해 게시를 중단한다. 다섯 image의 실제 합계도 다시 계산해 5 GiB 이하인지 확인하고, 개별·전체 상한과 실제 합계를 모두 release manifest에 남긴다. SBOM 생성과 CRITICAL 취약점 검사는 digest로 고정한 Trivy image 하나를 공유한다. workflow는 이 image를 직접 실행해 semantic version을 검증하고 scanner digest와 사람이 읽을 수 있는 버전을 release manifest와 실행 요약에 기록해 공급망 증적 생성 도구까지 추적한다. 실패 조건인 `CRITICAL` severity도 단일 설정으로 실제 검사 명령과 증적에 함께 전달해 검사 정책 drift를 차단한다. 서비스별 CRITICAL 검사 결과는 구조화된 Trivy JSON으로 저장해 SBOM artifact에 함께 보존하며, release manifest가 각 보고서 파일명과 SHA-256을 실제 내용에 결합한다.

현재 staging 서비스는 승인된 저비용 단일 호스트 topology로 `www.logitrack.kr`에서 운영된다. 이 구성은 자동 failover가 없는 테스트 환경이며 production 전환에는 별도의 다중 AZ 데이터 계층, backup 보존 정책, 무중단 migration과 비용 승인이 필요하다.

운영 배포에서는 `latest` tag를 사용하지 않고 Git commit SHA로 image를 고정한다. 애플리케이션 migration은 이전 버전과 호환되는 expand/contract 순서를 사용하며, 배포 성공 판정에는 API readiness뿐 아니라 주문 생성·배차·지도 경로 조회까지 포함한다.

로컬 빌드도 Dockerfile 기반 이미지와 Compose 외부 이미지를 `tag@sha256:digest`로 고정한다. 버전 갱신은 새 digest로 명시적으로 교체하고 CI의 전체 테스트·SBOM·취약점 검사를 함께 통과해야 한다.

Dependabot은 매주 GitHub Actions, Maven, npm, Python, Dockerfile, Docker Compose 의존성을 확인한다. minor/patch 갱신은 생태계별 단일 PR로 묶고 major 갱신은 독립 PR로 남겨 영향 범위를 명확히 하며, 고정된 컨테이너 tag의 새 digest도 같은 CI 게이트를 통과해야 한다.

Python의 직접 의존성은 각 `requirements.in`에 선언하고 Python 3.12 universal resolution으로 생성한 `requirements.txt`에 전이 의존성과 PyPI SHA-256을 모두 고정한다. analytics·simulator image와 CI는 `pip --require-hashes`로만 설치하므로 버전이 같아도 승인되지 않은 배포 파일은 거부한다. CI 전용 결합 lock은 애플리케이션 세 집합과 pytest를 한 번에 검증한다.

직접 의존성을 변경한 뒤 `./scripts/compile-python-locks.ps1`를 실행해 네 lock을 함께 갱신한다. 생성기는 digest 고정된 uv 0.12.17 image, Python 3.12 universal resolution과 named metadata cache를 사용한다. 생성 결과는 테스트와 image build를 통과한 뒤에만 커밋한다.

모든 pull request는 GitHub dependency review를 별도 필수 검사로 통과해야 한다. PR이 새로 도입하는 moderate 이상 알려진 취약 의존성을 차단하고, dependency graph snapshot 생성 지연은 최대 120초 동안만 재시도한다. workflow는 `pull_request`의 read-only contents 권한에서 SHA로 고정된 단일 action만 실행한다.

각 production image build context는 `.dockerignore`로 `.env*`, 로컬 build/cache, test artifact를 제외한다. OpenTelemetry Collector context는 Dockerfile만 허용하며 CI가 필수 제외 규칙의 누락을 차단한다.

## 로컬 릴리스 검증

`./scripts/container-build.ps1`은 API, analytics, simulator, web, OpenTelemetry Collector production image를 현재 commit SHA label과 함께 빌드하고 root runtime을 거부한다. 이어서 `./scripts/container-security.ps1`을 실행하면 digest로 고정한 Trivy 0.74.0이 `work/sbom/*.cdx.json`을 만들고 다섯 image의 CRITICAL 취약점 0건을 강제한다. 실제 registry push나 배포는 수행하지 않는다.

SBOM은 업로드 전에 `scripts/sbom-smoke.py`로 검증한다. 정확히 다섯 서비스의 CycloneDX 1.7 문서인지, 각 문서의 container image tag·SHA-256 image ID·구성요소 reference·OCI revision label이 현재 commit과 일치하는지 확인하며, 하나라도 불일치하면 artifact 게시를 차단한다.

API는 Spring Boot 3.4.13을 사용하며, 2026년 공개 취약점이 수정된 정식 릴리스 Tomcat 10.1.60과 Netty 4.1.137.Final을 명시적으로 고정한다. 프레임워크의 기본 관리 버전으로 되돌릴 때도 image scan이 통과해야 한다.

웹 production runtime에는 `node` 실행 파일과 standalone 산출물만 남기고, 빌드 단계에서만 필요한 npm, Corepack, Yarn은 제거한다. 패키지 설치와 TypeScript/Next.js build는 앞선 격리 stage에서 계속 잠금 파일을 기준으로 수행한다.

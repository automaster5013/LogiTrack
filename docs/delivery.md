# CI/CD와 릴리스 전략

## 현재 상태

- CI는 구현되어 있다. GitHub Actions가 API 테스트와 coverage, Python 테스트, Compose 구성, TypeScript build를 검증한다.
- production Docker image 네 개도 clean runner에서 빌드하고 모든 runtime이 non-root인지 검사한다.
- CD는 아직 구현하지 않았다. 승인된 배포 대상이 없으므로 image registry push나 외부 인프라 변경을 수행하지 않는다.

## CD를 시작할 시점

현재 코드 품질과 컨테이너 재현성이 갖춰졌으므로 스테이징 CD 설계를 시작하기 좋은 상태다. 실제 자동 배포는 아래 조건을 먼저 확정한 뒤 시작한다.

1. 배포 대상과 소유 계정, 리전 또는 호스팅 위치
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

운영 배포에서는 `latest` tag를 사용하지 않고 Git commit SHA로 image를 고정한다. 애플리케이션 migration은 이전 버전과 호환되는 expand/contract 순서를 사용하며, 배포 성공 판정에는 API readiness뿐 아니라 주문 생성·배차·지도 경로 조회까지 포함한다.

## 로컬 릴리스 검증

`./scripts/container-build.ps1`은 API, analytics, simulator, web production image를 현재 commit SHA label과 함께 빌드하고 root runtime을 거부한다. 실제 registry push나 배포는 수행하지 않는다.

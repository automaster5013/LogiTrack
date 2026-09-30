# 프로덕션 cutover gate

프로덕션 인프라는 자동 apply하지 않는다. 변경 책임자는 적용할 Git commit과 모든 계획·승인·훈련 증적을 하나의 JSON manifest에 고정한 뒤 아래 게이트를 통과시켜야 한다.

```powershell
python scripts/production-cutover-preflight.py work/production-cutover.json --revision <40-character-main-sha>
```

Manifest는 `schema_version: 1`과 다음 정보를 포함한다.

- `change_ticket_url`: 자격 증명을 포함하지 않은 HTTPS 변경 티켓
- `approvals`: 서로 다른 담당자의 `business`, `security`, `operations` 승인과 최근 7일 이내 시각
- `window`: 앞으로 30일 안에 시작하고 4시간을 넘지 않는 UTC 변경 창
- `terraform_plans`: state, alerting, audit, certificates, data, compute, edge 7개 root 각각의 동일 revision, plan SHA-256, 최근 24시간 생성 시각, `destructive_changes: false`
- `readiness`: regional/global paging 구독 `confirmed`, origin/viewer 인증서 `issued`, 30~300초 DNS TTL
- `drills`: 최근 30일 안에 통과한 backup/restore, regional failover, load, rollback 훈련과 HTTPS 증적
- `rollback`: 담당자, 30분 이하 실행 기한, 두 개 이상의 정량 trigger, 최근 30일 이내 테스트 시각

`production-state` bootstrap plan은 승인된 관리자 workstation에서 생성한다. 나머지 여섯 root는 GitHub의 수동 `Production Terraform plan evidence` workflow로 현재 main SHA를 지정해 한 번씩 생성한다. 각 run은 `production-plan` 환경 승인을 거친 뒤 비파괴 plan만 허용하고, plaintext 대신 GPG 암호화 plan과 attested evidence JSON을 7일간 보존한다. evidence의 `root`, `revision`, `planned_at`, `sha256`, `destructive_changes`를 manifest의 해당 항목에 복사하고 실제 apply 직전 복호화한 plan의 SHA-256을 다시 대조한다.

게이트 성공은 apply 권한을 대신하지 않는다. 승인된 plan digest를 다시 확인하고 `production-state → production-alerting → production-audit → production-certificates → production-data → production-compute → production-edge` 순서로 적용한다. 각 단계마다 출력과 실제 AWS 상태를 확인하고 다음 단계로 진행한다. DNS 전환 뒤 외부 헬스·로그·paging test가 실패하거나 manifest의 rollback trigger가 충족되면 즉시 이전 origin/DNS로 되돌리고 변경 티켓에 증적을 보존한다.

## 검증된 plan 적용

GPG private key와 apply 권한은 GitHub 밖의 승인된 관리자 workstation에만 둔다. 암호화 artifact를 내려받아 GitHub attestation을 확인하고 plan을 복호화한 뒤, 저장소 밖의 승인된 ledger 경로를 사용해 먼저 실행 없는 검증을 수행한다.

```powershell
python scripts/production-apply-guard.py --manifest <manifest.json> --evidence <production-state.evidence.json> --plan-file <production-state.tfplan> --ledger <vault-path/apply-ledger.json> --root state --revision <main-sha>
```

검증 성공 후 같은 명령에 `--execute --confirmation "APPLY production-state <main-sha>"`를 추가한다. guard는 현재 시간이 승인된 변경 창 안인지 다시 검사하고, manifest·evidence·복호화 plan의 SHA-256과 revision을 대조하며, 깨끗한 `main` checkout인지 확인한다. Terraform이 성공한 뒤에만 ledger를 원자적으로 갱신한다.

각 apply 직후 다음 명령으로 Terraform 출력과 실제 AWS 상태를 대조한다. receipt와 ledger는 모두 저장소 밖의 승인된 증적 경로에 둔다.

```powershell
python scripts/production-post-apply-verify.py --root state --revision <main-sha> --account-id <12-digit-aws-account-id> --ledger <vault-path/apply-ledger.json> --receipt <vault-path/production-state-verification.json>
```

검증기는 활성 AWS 계정을 확인하고 root별 핵심 상태를 읽는다. 원격 state 보호, 확인된 paging 구독, CloudTrail·Object Lock, 인증서 만료 여유, RDS·Valkey·MSK 가용성, ECS rollout·target health, CloudFront·WAF 연결이 모두 정상일 때만 receipt SHA-256과 검증 시각을 ledger에 원자적으로 기록한다. apply guard는 직전 root에 이 receipt가 없으면 다음 root 적용을 거부한다. 실패 시 다음 root로 진행하지 말고 원인을 복구하거나 rollback 기준에 따라 중단한다. plan을 재생성하거나 manifest를 수정했다면 기존 ledger를 재사용하지 말고 전체 승인을 다시 받는다.

## Cutover 완료 증적

일곱 root가 모두 적용·검증되고 DNS 전환이 끝난 뒤 최종 완료 게이트를 실행한다. `--receipt-dir`에는 앞 단계에서 만든 `production-<root>-verification.json` 일곱 개가 있어야 하며 완료 receipt도 저장소 밖에 보존한다.

```powershell
python scripts/production-cutover-complete.py --manifest <manifest.json> --ledger <vault-path/apply-ledger.json> --receipt-dir <vault-path/root-receipts> --completion-receipt <vault-path/cutover-completion.json> --revision <main-sha> --account-id <12-digit-aws-account-id>
```

게이트는 승인 변경 창이 아직 유효하고 manifest digest가 ledger와 일치하는지, ledger가 정확한 순서로 완결됐는지, 모든 root receipt의 SHA-256·revision·AWS 계정·plan·manifest·검증 시각이 ledger와 일치하는지 확인한다. 이어서 TLS 1.2 이상의 공개 `www.logitrack.kr`에서 production runtime revision, 최근 build, 비캐시 JSON metadata, 브랜드 응답과 HSTS·CSP를 확인한 뒤에만 불변 completion receipt를 만든다. 이 명령이 성공하기 전에는 변경 티켓을 완료 처리하지 않는다.

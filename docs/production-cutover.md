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

# 저비용 staging 런타임

이 Terraform root는 `www.logitrack.kr` 테스트 서비스를 위한 단일 호스트 런타임을 정의한다. `t3a.medium` EC2, 암호화된 30 GiB gp3, Elastic IP, Route 53 A record, GitHub OIDC 배포 역할, SSM 관리 권한, 일일 EBS snapshot, 암호화 S3 PostgreSQL dump, EC2 자동 시스템 복구와 월 USD 70 budget alert를 만든다. NAT Gateway, ALB, RDS, MSK와 SSH ingress는 만들지 않는다. 인터넷에는 Caddy의 80/443만 열리고 PostgreSQL, Redis, Kafka는 Docker internal network와 named volume에 남는다.

이 구성은 비용을 우선한 단일 장애 도메인 staging 설계다. API termination protection을 활성화하고 instance 내부 shutdown은 terminate 대신 stop으로 처리한다. EC2 system status check가 2분 연속 실패하면 동일 instance를 AWS가 자동 복구한다. database volume은 instance root EBS에 있고 매일 03:00 KST(18:00 UTC)에 crash-consistent snapshot을 생성해 최신 7개를 보존한다. 매일 03:30 KST에는 PostgreSQL custom dump를 별도 비공개 S3 bucket에 AES256으로 업로드하고 8일 후 만료한다. 자동 시스템 복구와 백업들은 다중 AZ failover나 point-in-time database recovery를 제공하지 않으므로 운영 환경에는 적합하지 않다.

## 월 비용 추정

2026-09-23 AWS Price List API의 서울 리전 Linux on-demand 단가를 기준으로 `t3a.medium`은 시간당 USD 0.0468, 730시간에 약 USD 34.16이다. gp3 30 GiB 약 USD 2.7, public IPv4 약 USD 3.65, 기존 Route 53 zone의 query와 ECR/전송량 및 증분 snapshot 여유분 USD 5~17을 합쳐 정상적인 저부하 월 비용은 약 **USD 41~58**으로 예상한다. T3 Unlimited CPU credit, snapshot 변경량, 인터넷 전송량, 기존 Cognito Plus 사용량이 커지면 증가할 수 있다. Budget은 80% 실제 비용과 100% forecast에서 알리지만 리소스를 자동 중단하는 hard cap은 아니다.

## 승인 후 최초 적용

적용 전 아래 네 SecureString을 먼저 만든다. 값은 Terraform 변수나 state, GitHub secret에 넣지 않는다. PostgreSQL 비밀번호는 Compose의 안전한 비대화형 주입을 위해 32~128자의 영숫자로 제한한다.

```powershell
$DbPassword = -join ((1..48) | ForEach-Object { 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'[(Get-Random -Maximum 62)] })
aws ssm put-parameter --profile logitrack-test-admin --region ap-northeast-2 --type SecureString --name /logitrack/staging/postgres-password --value $DbPassword --overwrite
aws ssm put-parameter --profile logitrack-test-admin --region ap-northeast-2 --type SecureString --name /logitrack/staging/cognito-authorization-base-url --value https://auth.logitrack.kr --overwrite
aws ssm put-parameter --profile logitrack-test-admin --region ap-northeast-2 --type SecureString --name /logitrack/staging/cognito-issuer-uri --value <auth Terraform issuer_uri> --overwrite
aws ssm put-parameter --profile logitrack-test-admin --region ap-northeast-2 --type SecureString --name /logitrack/staging/cognito-client-id --value <auth Terraform client_id> --overwrite
```

그 다음 ignored `terraform.tfvars`에 budget alert email을 설정하고 기존 encrypted S3 state backend를 사용해 plan을 검토한다.

```powershell
terraform -chdir=infra/aws/runtime init -reconfigure `
  -backend-config="bucket=logitrack-terraform-state-816954358294" `
  -backend-config="key=runtime/test/terraform.tfstate" `
  -backend-config="region=ap-northeast-2" `
  -backend-config="encrypt=true" `
  -backend-config="use_lockfile=true" `
  -backend-config="profile=logitrack-test-admin"
terraform -chdir=infra/aws/runtime plan -var-file=terraform.tfvars -out=runtime.tfplan
terraform -chdir=infra/aws/runtime show runtime.tfplan
```

승인된 plan에만 `terraform apply runtime.tfplan`을 실행한다. apply 후 `github_environment_variables` output의 `AWS_RUNTIME_ROLE_ARN`, `AWS_RUNTIME_INSTANCE_ID`를 GitHub `staging` environment variable에 추가한다. 기존 `AWS_REGION`, `AWS_ACCOUNT_ID`는 동일 값이어야 한다. GitHub environment의 deployment branch/tag rule은 반드시 `main`만 허용하고 required reviewer를 유지한다. 직접 등록한 Budget email 수신자는 별도 구독 확인이 필요하지 않으며 임계값을 넘을 때 알림을 받는다. SNS topic을 추가한 경우에만 SNS 구독 확인 절차가 필요하다.

## 배포와 롤백

1. `Publish staging images`를 main의 full SHA로 실행하고 성공 run ID를 기록한다.
2. `Deploy staging runtime`에 같은 SHA와 publication run ID를 전달한다.
3. workflow는 정확한 release-manifest artifact, AWS 계정/리전/플랫폼, 다섯 ECR digest의 존재를 재검증한다.
4. OIDC 단기 자격 증명으로 지정 EC2에만 SSM Run Command를 보내 digest URI를 pull한다.
5. Compose health와 외부 HTTPS/HSTS 검증이 끝나야 성공한다. 실패하면 배포 스크립트가 `/opt/logitrack/current`를 직전 release로 되돌리고 이전 Compose를 다시 올린다.

수동 롤백은 SSM Session Manager에서 `/opt/logitrack/releases/<previous-sha>`를 확인한 뒤 current symlink를 그 경로로 바꾸고 해당 directory의 `.env`와 `compose.yml`로 `docker compose up -d --remove-orphans --wait`를 실행한다. 데이터 volume은 release 간 공유되므로 destructive schema migration은 이 테스트 배포 경로에 넣지 않는다. 현재와 직전 release만 로컬에 보존하고 ECR에는 bootstrap lifecycle에 따라 최신 30개 image를 보존한다.

## 운영 확인

전체 운영 경계를 한 번에 읽기 전용으로 감사하려면 AWS CLI와 PowerShell이 설치된 관리자 환경에서 다음을 실행한다. 계정, IAM runtime·publisher·deployer 역할, ECR 불변성·scan·암호화·보존, instance·disk·보안 그룹, DNS, 자동 복구, snapshot, S3 backup, SSM 일정과 Budget 중 하나라도 기대값에서 벗어나면 즉시 실패한다. 일일 EBS snapshot과 PostgreSQL dump는 기본 30시간 안에 생성된 최신 artifact여야 하며 암호화도 검사한다. 새 DLM policy에는 첫 실행 전까지 같은 시간의 초기 grace period만 허용한다.

```powershell
./scripts/aws-runtime-audit.ps1
```

```bash
curl --fail --proto '=https' --tlsv1.2 https://www.logitrack.kr/login
curl -I https://www.logitrack.kr/login
aws ssm start-session --target <instance-id> --profile logitrack-test-admin --region ap-northeast-2
sudo docker compose --project-directory /opt/logitrack/current --env-file /opt/logitrack/current/.env -f /opt/logitrack/current/compose.yml ps
aws dlm get-lifecycle-policy --policy-id <snapshot_policy_id> --profile logitrack-test-admin --region ap-northeast-2
aws ssm describe-association-executions --association-id <postgres_backup_association_id> --profile logitrack-test-admin --region ap-northeast-2
aws s3api list-objects-v2 --bucket <backup_bucket_name> --prefix postgres/ --profile logitrack-test-admin --region ap-northeast-2
aws cloudwatch describe-alarms --alarm-names <system_recovery_alarm_name> --profile logitrack-test-admin --region ap-northeast-2
```

CloudWatch Logs를 기본 활성화하지 않아 고정 수집 비용을 피한다. 문제 조사에는 bounded Docker json logs와 SSM Session Manager를 사용한다. root 권한 사용자는 Docker inspect로 container environment를 볼 수 있으므로 instance role과 SSM 접근을 배포 관리자에게만 제한해야 한다.

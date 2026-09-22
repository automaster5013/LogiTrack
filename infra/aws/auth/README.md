# Cognito 운영자 인증

`www.logitrack.kr` 운영 콘솔용 관리자 생성 전용 Cognito Plus User Pool, WebAuthn 패스키, OAuth code/PKCE public client, 위협 보호, 역할 그룹과 `auth.logitrack.kr` custom domain을 만든다. 실제 계정·Route 53 zone·us-east-1 ACM 인증서가 필요하므로 CI에서는 `init -backend=false`와 `validate`만 실행하고 자동 apply하지 않는다.

```bash
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

적용 후 outputs를 웹/API 비밀 설정에 주입한다. Terraform AWS provider가 Cognito의 `FactorConfiguration`을 지원하기 전까지 User Pool을 만든 직후 아래 설정을 한 번 적용하고 `get-user-pool-mfa-config`로 확인한다. 이 설정은 사용자 확인이 된 패스키를 MFA 수준의 첫 인증 요소로 강제한다.

```bash
aws cognito-idp set-user-pool-mfa-config \
  --user-pool-id "$(terraform output -raw user_pool_id)" \
  --web-authn-configuration RelyingPartyId=auth.logitrack.kr,UserVerification=required,FactorConfiguration=MULTI_FACTOR_WITH_USER_VERIFICATION
```

일반 운영자 계정은 `ADMIN` 권한으로 생성하지 않는다. 초기 임시 비밀번호 로그인 뒤 `/passkeys/add`에서 패스키를 등록하고, 등록 확인 후 일상 로그인은 패스키만 사용한다. `ADMIN`과 `RECOVERY_OPERATOR` 그룹 변경 권한은 별도 배포 관리자 역할에만 둔다.

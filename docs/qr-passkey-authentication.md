# 운영자 QR·패스키 인증 설계

## 결정

운영자 로그인은 Amazon Cognito Managed Login의 WebAuthn 패스키를 사용한다. 데스크톱 브라우저에서 `다른 기기 사용`을 선택하면 WebAuthn/CTAP2 하이브리드 전송이 일회성 QR을 표시하고, 운영자는 등록된 휴대폰에서 생체 인증으로 서명한다. QR 자체를 자격 증명으로 취급하거나 LogiTrack이 고유 QR 프로토콜을 만들지 않는다.

운영 도메인은 다음처럼 분리한다.

- `www.logitrack.kr`: 공개 `/` 및 `/showcase`, 인증이 필요한 `/console` 운영 콘솔, 서버측 BFF
- `auth.logitrack.kr`: Cognito Managed Login 사용자 인터페이스
- Cognito WebAuthn RP ID: `auth.logitrack.kr` (공개 전 확정하며 변경하지 않음)
- OAuth callback: `https://www.logitrack.kr/auth/callback` 한 개만 등록

## 로그인 흐름

1. 브라우저가 `/auth/login`을 요청한다.
2. BFF는 암호학적 난수 `state`, `nonce`, PKCE verifier를 만들고 5분 수명의 `__Host-`, `HttpOnly`, `Secure`, `SameSite=Lax` 쿠키에 저장한다.
3. Cognito `/oauth2/authorize`로 Authorization Code + PKCE 요청을 보낸다.
4. Cognito Managed Login에서 패스키를 선택한다. 교차 기기 인증 시 브라우저/OS가 QR을 만들고 휴대폰은 사용자 확인 후 origin/RP-bound 서명을 생성한다.
5. callback은 `state`를 대조하고 code를 PKCE verifier와 교환한다.
6. ID token은 Cognito JWKS 서명, issuer, audience, 5분 이내 발급, nonce를 모두 검증한다.
7. access token만 `HttpOnly` 쿠키에 최대 1시간 보관한다. refresh token은 저장하지 않으며 세션 만료 시 재인증한다.
8. 브라우저 JavaScript는 토큰을 읽지 않는다. `/backend/api/**` BFF가 허용된 경로·헤더만 내부 API에 전달한다.
9. API는 다시 JWT 서명/issuer와 `token_use=access`, 정확한 `client_id`를 검증하고 `cognito:groups`를 역할로 변환한다.

## 역할과 운영자 수명주기

| Cognito 그룹 | 권한 |
| --- | --- |
| `VIEWER` | 조회와 보고서 다운로드 |
| `OPERATOR` | 주문·배차·입출고·경고 확인 |
| `RECOVERY_OPERATOR` | DLQ/outbox 복구 작업 |
| `ADMIN` | 경고 정책과 삭제를 포함한 전체 관리 |

공개 회원가입은 비활성화하고 운영자 계정은 관리자만 생성한다. 최초 임시 인증 후 패스키를 등록하며 `UserVerification=required`, `FactorConfiguration=MULTI_FACTOR_WITH_USER_VERIFICATION`를 사용한다. 일상 운영에는 개인별 계정만 허용하며 공유 계정을 금지한다. 퇴사·역할 변경은 Cognito 그룹 제거와 계정 비활성화를 즉시 수행하고, 분기마다 접근 권한을 재검토한다.

최소 두 개의 break-glass 관리자 계정은 별도 하드웨어 보안키 두 개와 함께 오프라인 보관한다. 일반 운영자가 `ADMIN`이나 `RECOVERY_OPERATOR` 그룹을 스스로 부여할 수 없게 IAM을 분리한다.

## 공격 방어

- QR 캡처/재생: WebAuthn challenge와 하이브리드 세션이 짧은 수명·일회성이며 origin/RP에 묶인다.
- 피싱: 패스키 서명은 `auth.logitrack.kr` RP에서만 유효하다. 유사 도메인 인증은 실패한다.
- OAuth CSRF/code 탈취: state + PKCE S256 + nonce와 정확한 callback allowlist로 차단한다.
- XSS 토큰 탈취: 토큰을 JavaScript나 local/session storage에 노출하지 않고 HttpOnly 쿠키와 BFF를 사용한다.
- 권한 상승: UI가 아니라 API에서 역할을 강제하고, Cognito access token의 client ID와 token type을 검증한다.
- 헤더 위조: API 감사 actor는 외부 `X-Operator` 값을 무시하고 검증된 JWT subject로 덮어쓴다.
- 세션 도용: TLS 전용, Secure 쿠키, 최대 1시간 세션, refresh token 미사용, 로그아웃 시 모든 인증 쿠키·브라우저 저장소를 제거한다. 로그아웃 POST는 명시적 교차 출처 요청을 거부한다.
- 자동 공격: AWS WAF rate-based rule, Cognito 위협 보호, CloudWatch 인증 실패 경보를 배포 단계에서 활성화한다.

## 운영 배포 설정

웹 런타임에는 `AUTH_REQUIRED=true`, `COGNITO_AUTHORIZATION_BASE_URL=https://auth.logitrack.kr`, `COGNITO_ISSUER_URI=https://cognito-idp.<region>.amazonaws.com/<pool-id>`, `COGNITO_CLIENT_ID`, `OIDC_REDIRECT_URI=https://www.logitrack.kr/auth/callback`, `OIDC_POST_LOGOUT_REDIRECT_URI=https://www.logitrack.kr/login`, `INTERNAL_API_URL=http://api:8080`을 주입한다. 웹 이미지는 `NEXT_PUBLIC_API_URL=/backend`로 빌드한다.

API에는 `SECURITY_ENABLED=true`, 동일한 issuer를 `SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI`, app client ID를 `SECURITY_CLIENT_ID`, `CORS_ALLOWED_ORIGINS=https://www.logitrack.kr`로 설정한다. 공개 DNS를 붙이기 전 Cognito RP ID, callback, logout URL을 확정한다. `http://www.logitrack.kr`는 어떤 콘텐츠도 제공하지 않고 HTTPS로 영구 리다이렉트한다.

## 배포 전 검증

- 등록된 패스키, 다른 휴대폰 QR, 하드웨어 키 로그인이 모두 성공한다.
- 다른 origin, 변조 state/nonce, 재사용 callback, ID token을 access token으로 사용한 요청이 실패한다.
- VIEWER가 POST/DELETE/복구 API에 접근하면 403, 미인증 요청은 401이다.
- access token 쿠키가 JavaScript에서 보이지 않고 로그·오류 응답에 출력되지 않는다.
- 패스키 분실·운영자 비활성화·그룹 제거가 1시간 이내 모든 세션에서 반영된다.
- `/`와 `/showcase`, health check만 인증 없이 접근 가능하다.
- 인증이 성공하면 콜백은 공개 showcase가 아닌 `/console` 운영 화면으로 이동한다.

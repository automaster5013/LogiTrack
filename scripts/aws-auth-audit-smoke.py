from pathlib import Path


source = Path("scripts/aws-auth-audit.ps1").read_text(encoding="utf-8")
required = (
    '"sts", "get-caller-identity"',
    '"cognito-idp", "list-user-pools"',
    '"cognito-idp", "describe-user-pool"',
    'DeletionProtection -eq "ACTIVE"',
    'UserPoolTier -eq "PLUS"',
    "AllowAdminCreateUserOnly",
    "AllowedFirstAuthFactors",
    'AdvancedSecurityMode -eq "ENFORCED"',
    '"cognito-idp", "get-user-pool-mfa-config"',
    'FactorConfiguration -eq "MULTI_FACTOR_WITH_USER_VERIFICATION"',
    '"cognito-idp", "describe-user-pool-client"',
    "ClientSecret",
    "PreventUserExistenceErrors",
    "EnableTokenRevocation",
    "AllowedOAuthFlows",
    "CallbackURLs",
    "TokenValidityUnits",
    '"cognito-idp", "describe-managed-login-branding-by-client"',
    '"cognito-idp", "describe-user-pool-domain"',
    'SecurityPolicy -eq "TLS_V1_2_2021"',
    '"acm", "describe-certificate"',
    "MinimumCertificateDays",
    '"route53", "list-resource-record-sets"',
    '"cognito-idp", "list-groups"',
    "RECOVERY_OPERATOR = 20",
)
missing = [control for control in required if control not in source]
if missing:
    raise SystemExit("ERROR: AWS auth audit is missing controls: " + ", ".join(missing))
if any(token in source for token in ("remove-", "delete-", "set-", "update-", "create-", "associate-", "disassociate-")):
    raise SystemExit("ERROR: AWS auth audit must remain read-only")
print("PASS: AWS auth audit covers Cognito identity, passkey, OAuth, domain, certificate, DNS, and role boundaries")

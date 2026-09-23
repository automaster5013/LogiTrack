param(
  [string]$Profile = "logitrack-test-admin",
  [string]$Region = "ap-northeast-2",
  [string]$ExpectedAccountId = "816954358294",
  [string]$HostedZoneId = "Z05031871LL3C3WCCPUJO",
  [string]$Environment = "test",
  [string]$AuthDomain = "auth.logitrack.kr",
  [ValidateRange(14, 90)][int]$MinimumCertificateDays = 30
)

$ErrorActionPreference = "Stop"
$env:AWS_PAGER = ""

function Invoke-AwsJson {
  param([Parameter(Mandatory)][string[]]$Arguments, [string]$AwsRegion = $Region)
  $raw = & aws @Arguments --profile $Profile --region $AwsRegion --output json --no-cli-pager
  if ($LASTEXITCODE -ne 0) { throw "AWS CLI failed: aws $($Arguments -join ' ')" }
  return ($raw | ConvertFrom-Json)
}

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "AUDIT FAILED: $Message" }
}

function Assert-ExactSet {
  param([object[]]$Actual, [object[]]$Expected, [string]$Message)
  Assert-True ((@($Actual | Sort-Object) -join ",") -eq (@($Expected | Sort-Object) -join ",")) $Message
}

$identity = Invoke-AwsJson @("sts", "get-caller-identity")
Assert-True ($identity.Account -eq $ExpectedAccountId) "unexpected AWS account $($identity.Account)"

$poolName = "logitrack-$Environment-operators"
$poolList = Invoke-AwsJson @("cognito-idp", "list-user-pools", "--max-results", "60")
$poolMatches = @($poolList.UserPools | Where-Object Name -eq $poolName)
Assert-True ($poolMatches.Count -eq 1) "expected exactly one $poolName user pool"
$poolId = [string]$poolMatches[0].Id
$pool = (Invoke-AwsJson @("cognito-idp", "describe-user-pool", "--user-pool-id", $poolId)).UserPool

Assert-True ($pool.DeletionProtection -eq "ACTIVE" -and $pool.UserPoolTier -eq "PLUS") "user pool deletion protection or tier drifted"
Assert-ExactSet @($pool.UsernameAttributes) @("email") "user pool sign-in identifier drifted"
Assert-ExactSet @($pool.AutoVerifiedAttributes) @("email") "user pool verification attribute drifted"
Assert-ExactSet @($pool.UserAttributeUpdateSettings.AttributesRequireVerificationBeforeUpdate) @("email") "email changes can replace the verified sign-in address before ownership verification"
Assert-True ($pool.AdminCreateUserConfig.AllowAdminCreateUserOnly -eq $true) "public self-registration is enabled"
Assert-True ($pool.MfaConfiguration -eq "OFF") "unexpected legacy MFA configuration"
Assert-ExactSet @($pool.Policies.SignInPolicy.AllowedFirstAuthFactors) @("PASSWORD", "WEB_AUTHN") "first authentication factors drifted"
$password = $pool.Policies.PasswordPolicy
Assert-True ($password.MinimumLength -eq 16 -and $password.RequireUppercase -and $password.RequireLowercase -and $password.RequireNumbers -and $password.RequireSymbols -and $password.TemporaryPasswordValidityDays -eq 1) "password bootstrap policy drifted"
Assert-True ($pool.UserPoolAddOns.AdvancedSecurityMode -eq "ENFORCED") "Cognito threat protection is not enforced"
$recovery = @($pool.AccountRecoverySetting.RecoveryMechanisms)
Assert-True ($recovery.Count -eq 1 -and $recovery[0].Name -eq "verified_email" -and $recovery[0].Priority -eq 1) "account recovery policy drifted"
Assert-True ($pool.UserPoolTags.Application -eq "LogiTrack" -and $pool.UserPoolTags.Environment -eq $Environment -and $pool.UserPoolTags.ManagedBy -eq "terraform") "user pool tags drifted"

$mfa = Invoke-AwsJson @("cognito-idp", "get-user-pool-mfa-config", "--user-pool-id", $poolId)
Assert-True ($mfa.WebAuthnConfiguration.RelyingPartyId -eq $AuthDomain -and $mfa.WebAuthnConfiguration.UserVerification -eq "required" -and $mfa.WebAuthnConfiguration.FactorConfiguration -eq "MULTI_FACTOR_WITH_USER_VERIFICATION") "WebAuthn relying-party or user-verification boundary drifted"

$clientName = "logitrack-$Environment-web"
$clientList = Invoke-AwsJson @("cognito-idp", "list-user-pool-clients", "--user-pool-id", $poolId, "--max-results", "60")
$clientMatches = @($clientList.UserPoolClients | Where-Object ClientName -eq $clientName)
Assert-True ($clientMatches.Count -eq 1) "expected exactly one $clientName app client"
$clientId = [string]$clientMatches[0].ClientId
$client = (Invoke-AwsJson @("cognito-idp", "describe-user-pool-client", "--user-pool-id", $poolId, "--client-id", $clientId)).UserPoolClient
Assert-True ([string]::IsNullOrWhiteSpace([string]$client.ClientSecret)) "public PKCE client unexpectedly has a client secret"
Assert-True ($client.AllowedOAuthFlowsUserPoolClient -and $client.PreventUserExistenceErrors -eq "ENABLED" -and $client.EnableTokenRevocation) "OAuth client protection drifted"
Assert-ExactSet @($client.AllowedOAuthFlows) @("code") "OAuth grant flow drifted"
Assert-ExactSet @($client.AllowedOAuthScopes) @("openid", "profile") "OAuth scopes drifted"
Assert-ExactSet @($client.SupportedIdentityProviders) @("COGNITO") "identity provider set drifted"
Assert-ExactSet @($client.ExplicitAuthFlows) @("ALLOW_USER_AUTH", "ALLOW_REFRESH_TOKEN_AUTH") "explicit authentication flows drifted"
Assert-ExactSet @($client.CallbackURLs) @("https://www.logitrack.kr/auth/callback") "OAuth callback allowlist drifted"
Assert-ExactSet @($client.LogoutURLs) @("https://www.logitrack.kr/login") "OAuth logout allowlist drifted"
Assert-True ($client.AccessTokenValidity -eq 1 -and $client.IdTokenValidity -eq 1 -and $client.RefreshTokenValidity -eq 1 -and $client.TokenValidityUnits.AccessToken -eq "hours" -and $client.TokenValidityUnits.IdToken -eq "hours" -and $client.TokenValidityUnits.RefreshToken -eq "days") "token validity boundary drifted"

$branding = (Invoke-AwsJson @("cognito-idp", "describe-managed-login-branding-by-client", "--user-pool-id", $poolId, "--client-id", $clientId)).ManagedLoginBranding
Assert-True ($branding.UserPoolId -eq $poolId -and $branding.UseCognitoProvidedValues -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$branding.ManagedLoginBrandingId)) "managed login branding drifted"

$domain = (Invoke-AwsJson @("cognito-idp", "describe-user-pool-domain", "--domain", $AuthDomain)).DomainDescription
Assert-True ($domain.UserPoolId -eq $poolId -and $domain.AWSAccountId -eq $ExpectedAccountId -and $domain.Status -eq "ACTIVE" -and $domain.ManagedLoginVersion -eq 2) "Cognito custom domain drifted"
Assert-True ($domain.CustomDomainConfig.SecurityPolicy -eq "TLS_V1_2_2021" -and -not [string]::IsNullOrWhiteSpace([string]$domain.CloudFrontDistribution)) "custom domain TLS or distribution drifted"

$certificate = (Invoke-AwsJson @("acm", "describe-certificate", "--certificate-arn", $domain.CustomDomainConfig.CertificateArn) -AwsRegion "us-east-1").Certificate
$remaining = [DateTimeOffset]::Parse([string]$certificate.NotAfter) - [DateTimeOffset]::UtcNow
Assert-True ($certificate.Status -eq "ISSUED" -and $certificate.Type -eq "AMAZON_ISSUED" -and $certificate.RenewalEligibility -eq "ELIGIBLE" -and $certificate.DomainName -eq $AuthDomain -and $remaining.TotalDays -ge $MinimumCertificateDays) "custom domain certificate is invalid or near expiry"

$recordSets = @((Invoke-AwsJson @("route53", "list-resource-record-sets", "--hosted-zone-id", $HostedZoneId)).ResourceRecordSets)
$authRecords = @($recordSets | Where-Object { $_.Name -eq "$AuthDomain." -and $_.Type -eq "A" })
Assert-True ($authRecords.Count -eq 1 -and $authRecords[0].AliasTarget.DNSName.TrimEnd(".") -eq $domain.CloudFrontDistribution -and $authRecords[0].AliasTarget.HostedZoneId -eq "Z2FDTNDATAQYW2" -and -not $authRecords[0].AliasTarget.EvaluateTargetHealth) "auth domain Route 53 alias drifted"

$groups = @((Invoke-AwsJson @("cognito-idp", "list-groups", "--user-pool-id", $poolId, "--limit", "60")).Groups)
$expectedGroups = @{ ADMIN = 10; RECOVERY_OPERATOR = 20; OPERATOR = 30; VIEWER = 40 }
Assert-ExactSet @($groups.GroupName) @($expectedGroups.Keys) "authorization group set drifted"
foreach ($group in $groups) {
  Assert-True ($group.Precedence -eq $expectedGroups[$group.GroupName] -and $group.Description -eq "LogiTrack $($group.GroupName) authorization group") "$($group.GroupName) authorization group drifted"
}

Write-Output "PASS: AWS Cognito authentication audit succeeded for $poolId ($AuthDomain)"

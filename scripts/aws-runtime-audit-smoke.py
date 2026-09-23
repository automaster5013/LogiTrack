from pathlib import Path


source = Path("scripts/aws-runtime-audit.ps1").read_text(encoding="utf-8")
required = (
    "sts\", \"get-caller-identity",
    "Assert-RoleBoundary",
    "list-attached-role-policies",
    "get-role-policy",
    "token.actions.githubusercontent.com:sub",
    "logitrack-staging-image-publisher",
    "describe-repositories",
    "ImageTagMutability",
    "ScanOnPush",
    "get-lifecycle-policy",
    "imageCountMoreThan",
    "disableApiTermination",
    "instanceInitiatedShutdownBehavior",
    "HttpTokens",
    "describe-instance-information",
    'PingStatus -eq "Online"',
    "LastPingDateTime",
    "AssociationStatus",
    "rootVolume.Encrypted",
    '($ports -join ",") -eq "80,443"',
    "Resolve-Ipv4WithRetry",
    "ec2:recover",
    "get-lifecycle-policy",
    "MaximumBackupAgeHours",
    "describe-snapshots",
    "latest managed EBS snapshot is stale or future-dated",
    "get-public-access-block",
    "get-bucket-encryption",
    "get-bucket-lifecycle-configuration",
    "list-objects-v2",
    "head-object",
    "latest PostgreSQL backup is stale or future-dated",
    "list-associations",
    "describe-association",
    "ApplyOnlyAtCronInterval",
    'backupTargets[0].Key -eq "InstanceIds"',
    'backupCommand.Contains("pg_restore --list")',
    "describe-budget",
    "describe-notifications-for-budget",
)
missing = [control for control in required if control not in source]
if missing:
    raise SystemExit("ERROR: AWS runtime audit is missing controls: " + ", ".join(missing))
if any(token in source for token in ("remove-", "delete-", "terminate-", "put-", "update-", "create-")):
    raise SystemExit("ERROR: AWS runtime audit must remain read-only")
print("PASS: AWS runtime audit covers compute, network, recovery, backup, and budget boundaries")

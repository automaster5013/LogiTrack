from pathlib import Path


source = Path("scripts/aws-runtime-audit.ps1").read_text(encoding="utf-8")
required = (
    "sts\", \"get-caller-identity",
    "disableApiTermination",
    "instanceInitiatedShutdownBehavior",
    "HttpTokens",
    "rootVolume.Encrypted",
    '($ports -join ",") -eq "80,443"',
    "ec2:recover",
    "get-lifecycle-policy",
    "get-public-access-block",
    "get-bucket-encryption",
    "get-bucket-lifecycle-configuration",
    "list-objects-v2",
    "head-object",
    "list-associations",
    "describe-budget",
    "describe-notifications-for-budget",
)
missing = [control for control in required if control not in source]
if missing:
    raise SystemExit("ERROR: AWS runtime audit is missing controls: " + ", ".join(missing))
if any(token in source for token in ("remove-", "delete-", "terminate-", "put-", "update-", "create-")):
    raise SystemExit("ERROR: AWS runtime audit must remain read-only")
print("PASS: AWS runtime audit covers compute, network, recovery, backup, and budget boundaries")

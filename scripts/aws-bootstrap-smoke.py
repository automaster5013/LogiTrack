import re
from pathlib import Path


ROOT = Path("infra/aws/bootstrap")
SERVICES = ("api", "analytics", "simulator", "web", "otel-collector")


def require(source: str, fragment: str) -> None:
    if fragment not in source:
        raise AssertionError(f"AWS bootstrap lacks required control: {fragment}")


def main() -> None:
    terraform_files = sorted(ROOT.glob("*.tf"))
    if not terraform_files:
        raise AssertionError("AWS bootstrap has no Terraform files")
    source = "\n".join(path.read_text(encoding="utf-8") for path in terraform_files)

    for fragment in (
        'required_version = ">= 1.16.0, < 2.0.0"',
        'version = "~> 6.0"',
        'image_tag_mutability = "IMMUTABLE"',
        "force_delete         = false",
        "prevent_destroy = true",
        "scan_on_push = true",
        'encryption_type = "AES256"',
        'resource "aws_ecr_lifecycle_policy" "service"',
        'tagStatus   = "untagged"',
        'countType   = "sinceImagePushed"',
        'countNumber = var.untagged_image_retention_days',
        'tagStatus   = "any"',
        'countType   = "imageCountMoreThan"',
        'countNumber = var.retained_images',
        'default     = 30',
        'default     = 7',
        'actions = ["sts:AssumeRoleWithWebIdentity"]',
        'variable = "token.actions.githubusercontent.com:aud"',
        'values   = ["sts.amazonaws.com"]',
        'variable = "token.actions.githubusercontent.com:sub"',
        "environment:${var.github_environment}",
        'default     = "staging"',
        'resources = values(aws_ecr_repository.service)[*].arn',
        'actions   = ["ecr:GetAuthorizationToken"]',
        'actions   = ["ecr:DescribeRepositories"]',
        '"ecr:DescribeImages"',
        "github_environment_variables",
        'data "aws_caller_identity" "current"',
        "AWS_ACCOUNT_ID        = data.aws_caller_identity.current.account_id",
    ):
        require(source, fragment)

    for service in SERVICES:
        if f'"{service}"' not in source:
            raise AssertionError(f"AWS bootstrap does not provision {service}")

    forbidden = (
        "aws_access_key",
        "aws_secret",
        "kaiser5013",
        "aws_ecs_",
        "aws_db_",
        "aws_route53_",
        "aws_acm_",
        "force_delete         = true",
        "prevent_destroy = false",
        'image_tag_mutability = "MUTABLE"',
    )
    for fragment in forbidden:
        if fragment.lower() in source.lower():
            raise AssertionError(f"AWS bootstrap contains forbidden scope or credential text: {fragment}")

    trust = re.search(
        r'variable = "token\.actions\.githubusercontent\.com:sub".*?values\s+=\s+\["([^"]+)"\]',
        source,
        re.DOTALL,
    )
    if not trust or trust.group(1) != "repo:${var.github_owner}/${var.github_repository}:environment:${var.github_environment}":
        raise AssertionError("OIDC subject is not restricted to one repository environment")

    print("PASS: AWS bootstrap is immutable, lifecycle-bounded, least-privilege, environment-scoped, and runtime-free")


if __name__ == "__main__":
    main()

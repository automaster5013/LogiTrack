import re
from pathlib import Path

import yaml


WORKFLOW_PATH = Path(".github/workflows/scorecard.yml")
PINNED_ACTION = re.compile(r"^[^@\s]+@[0-9a-f]{40}$")


def main() -> None:
    source = WORKFLOW_PATH.read_text(encoding="utf-8")
    workflow = yaml.safe_load(source)
    analysis = workflow["jobs"]["analysis"]

    if workflow.get("permissions") != "read-all":
        raise AssertionError("Scorecard workflow must default to read-only permissions")
    if analysis.get("permissions") != {"security-events": "write", "id-token": "write"}:
        raise AssertionError("Scorecard job permissions exceed SARIF and OIDC publication needs")
    if analysis.get("runs-on") != "ubuntu-24.04" or analysis.get("timeout-minutes") != 10:
        raise AssertionError("Scorecard runner or timeout is not bounded")
    if "pull_request" in source or "pull_request_target" in source:
        raise AssertionError("Scorecard must not receive write permissions for pull request code")
    for required in ("push:", "branches: [main]", "schedule:", "workflow_dispatch:"):
        if required not in source:
            raise AssertionError(f"Scorecard trigger is missing: {required}")

    steps = analysis.get("steps", [])
    actions = [step["uses"] for step in steps if "uses" in step]
    if len(actions) != 4 or not all(PINNED_ACTION.fullmatch(action) for action in actions):
        raise AssertionError(f"Scorecard actions must use four immutable SHAs: {actions}")
    checkout = steps[0]
    if checkout.get("with", {}).get("persist-credentials") is not False:
        raise AssertionError("Scorecard checkout must not persist credentials")
    scorecard = next(step for step in steps if step.get("name") == "Analyze repository security posture")
    if scorecard.get("with") != {
        "results_file": "results.sarif",
        "results_format": "sarif",
        "publish_results": True,
    }:
        raise AssertionError("Scorecard analysis output contract drifted")
    artifact = next(step for step in steps if step.get("name") == "Preserve SARIF evidence")
    if artifact.get("with", {}).get("retention-days") != 30:
        raise AssertionError("Scorecard SARIF evidence retention drifted")

    print("PASS: OpenSSF Scorecard triggers, permissions, action pins, SARIF, and evidence retention are bounded")


if __name__ == "__main__":
    main()

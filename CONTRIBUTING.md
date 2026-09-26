# Contributing to LogiTrack

Thank you for helping improve LogiTrack. Contributions that make logistics workflows easier to understand, operate, test, or recover are welcome.

## Before you start

- Search existing issues and pull requests to avoid duplicate work.
- For a substantial feature or architectural change, open a feature request before implementation so the scope and compatibility impact can be discussed.
- Report security vulnerabilities privately through the process in [SECURITY.md](SECURITY.md). Do not open a public issue for a suspected vulnerability.
- Follow the [Code of Conduct](CODE_OF_CONDUCT.md) in all project spaces.

## Good first contributions

- Clarify setup, architecture, operations, or recovery documentation.
- Add focused tests for an existing behavior or failure mode.
- Improve accessibility, empty states, or operator feedback in the web console.
- Reproduce a bug with a minimal failing test or deterministic script.
- Improve observability without exposing credentials, tokens, or personal data.

Issues suitable for a first contribution are labeled [`good first issue`](https://github.com/automaster5013/LogiTrack/labels/good%20first%20issue). Maintainer guidance is available on issues labeled [`help wanted`](https://github.com/automaster5013/LogiTrack/labels/help%20wanted).

## Local development

Requirements: Docker Desktop, Docker Compose v2, PowerShell 7, Java 21, Python 3.12, and Node.js 22.

```powershell
pwsh ./scripts/init-env.ps1
docker compose up --build --wait
```

The showcase is available at `http://localhost:3000/`, the operator console at `http://localhost:3000/console`, and the API health endpoint at `http://localhost:8080/actuator/health`.

Run the checks relevant to your change before opening a pull request:

```powershell
python -m unittest discover simulator/tests
python -m unittest discover analytics/tests
python scripts/compose-config-smoke.py
pwsh ./scripts/domain-coverage.ps1
Push-Location web; npm ci; npm test; npm run build; Pop-Location
```

For changes that cross service boundaries, start the stack and run `pwsh ./scripts/smoke.ps1`. Additional focused smoke tests are documented in [README.md](README.md#로컬-검증).

## Pull request workflow

1. Fork the repository and create a focused branch from the latest `main`.
2. Keep unrelated formatting or refactoring out of the change.
3. Add or update tests and documentation for changed behavior.
4. Use clear commit messages that describe the outcome.
5. Complete the pull request template and link the relevant issue.
6. Wait for the required CI, dependency review, and security checks.
7. Address review feedback with additional commits; do not rewrite shared history after review has started.

Pull requests are squash-merged. By submitting a contribution, you agree that it is provided under the repository's [Apache License 2.0](LICENSE).

## Design and security expectations

- Preserve event compatibility or document an explicit migration path.
- Keep credentials and environment-specific values out of source control, fixtures, screenshots, and logs.
- Prefer bounded retries, timeouts, resource limits, and deterministic cleanup for failure paths.
- Keep authorization checks at the server boundary; browser visibility is not access control.
- Include an operator-visible failure mode and recovery path for operational changes.
- Avoid adding dependencies when the platform or an existing dependency already provides the capability.

## Getting help

Use [GitHub Discussions](https://github.com/automaster5013/LogiTrack/discussions) for design questions and usage help. Use an issue only when there is a reproducible defect or a scoped enhancement proposal.

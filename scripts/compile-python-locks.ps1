$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$uvImage = "ghcr.io/astral-sh/uv@sha256:9a59bb7206905ccaae4f7dab222fbac47c125a21e5fc16f43f427cd6c940ade3"
$locks = @(
  @{ Input = "analytics/requirements.in"; Output = "analytics/requirements.txt" },
  @{ Input = "simulator/requirements.in"; Output = "simulator/requirements.txt" },
  @{ Input = "scripts/requirements.in"; Output = "scripts/requirements.txt" },
  @{ Input = "scripts/requirements-ci.in"; Output = "scripts/requirements-ci.txt" }
)

foreach ($lock in $locks) {
  & docker run --rm `
    --volume "${repositoryRoot}:/workspace" `
    --volume "logitrack-uv-cache:/root/.cache/uv" `
    --workdir /workspace `
    $uvImage uv --quiet pip compile `
    --python-version 3.12 `
    --universal `
    --generate-hashes `
    --output-file $($lock.Output) `
    $($lock.Input)
  if ($LASTEXITCODE -ne 0) { throw "Failed to compile $($lock.Output)" }
}

Write-Output "PASS: regenerated Python 3.12 universal SHA-256 requirement locks"

$ErrorActionPreference = "Stop"

$trivyImage = "ghcr.io/aquasecurity/trivy@sha256:62b1e65e8869bc4b4c6aa4fa2b21595256c7c2f6018a9d9ad61caf87187c1969"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$sbomDirectory = Join-Path $repositoryRoot "work\sbom"
New-Item -ItemType Directory -Force -Path $sbomDirectory | Out-Null

$images = @("api", "analytics", "simulator", "web", "otel-collector")
foreach ($service in $images) {
  $image = "logitrack-${service}:local-release"
  $sbomFile = "logitrack-${service}.cdx.json"
  $criticalReportFile = "logitrack-${service}.critical.json"

  docker run --rm `
    --volume /var/run/docker.sock:/var/run/docker.sock `
    --volume trivy-cache:/root/.cache/ `
    --mount "type=bind,source=$sbomDirectory,target=/output" `
    $trivyImage image --scanners vuln --format cyclonedx `
    --output "/output/$sbomFile" --no-progress $image
  if ($LASTEXITCODE -ne 0) { throw "Could not generate SBOM for $image" }

  $sbomPath = Join-Path $sbomDirectory $sbomFile
  if (-not (Test-Path $sbomPath) -or (Get-Item $sbomPath).Length -eq 0) {
    throw "SBOM is missing or empty: $sbomPath"
  }

  docker run --rm `
    --volume /var/run/docker.sock:/var/run/docker.sock `
    --volume trivy-cache:/root/.cache/ `
    --mount "type=bind,source=$sbomDirectory,target=/output" `
    $trivyImage image --scanners vuln --severity CRITICAL `
    --format json --output "/output/$criticalReportFile" `
    --exit-code 1 --no-progress $image
  if ($LASTEXITCODE -ne 0) {
    Get-Content (Join-Path $sbomDirectory $criticalReportFile)
    throw "Critical vulnerabilities detected in $image"
  }

  Write-Host "PASS: $image SBOM=$sbomPath critical vulnerabilities=0"
}

$revision = (git -C $repositoryRoot rev-parse HEAD).Trim()
python (Join-Path $PSScriptRoot "sbom-smoke.py") $sbomDirectory --tag local-release --revision $revision
if ($LASTEXITCODE -ne 0) { throw "Generated SBOM identity or provenance validation failed" }

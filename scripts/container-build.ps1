$ErrorActionPreference = "Stop"

$revision = (git rev-parse HEAD).Trim()
$images = @(
  @{ Name = "logitrack-api:local-release"; Context = ".\api" },
  @{ Name = "logitrack-analytics:local-release"; Context = ".\analytics" },
  @{ Name = "logitrack-simulator:local-release"; Context = ".\simulator" },
  @{ Name = "logitrack-web:local-release"; Context = ".\web" },
  @{ Name = "logitrack-otel-collector:local-release"; Context = ".\infra\otel" }
)

foreach ($image in $images) {
  docker build --label "org.opencontainers.image.revision=$revision" --tag $image.Name $image.Context
  if ($LASTEXITCODE -ne 0) { throw "Could not build $($image.Name)" }

  $runtimeUser = (docker image inspect --format '{{.Config.User}}' $image.Name).Trim()
  if ([string]::IsNullOrWhiteSpace($runtimeUser) -or $runtimeUser -in @("0", "root")) {
    throw "$($image.Name) runs as root"
  }
  Write-Host "PASS: $($image.Name) runtime user=$runtimeUser"
}

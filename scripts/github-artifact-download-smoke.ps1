$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "github-artifact-download.ps1")

$headers = @{ Authorization = "Bearer test-token" }
$archiveApiUri = [uri]"https://api.github.com/repos/automaster5013/LogiTrack/actions/artifacts/123/zip"
$destination = Join-Path ([System.IO.Path]::GetTempPath()) "artifact-smoke-$([guid]::NewGuid().ToString('N')).zip"
$authenticatedCalls = 0
$downloadCalls = 0
$authenticatedRequest = {
  param([uri]$RequestUri, [System.Collections.IDictionary]$RequestHeaders, [int]$RequestTimeoutSeconds)
  $script:authenticatedCalls++
  if ($RequestUri -ne $archiveApiUri -or $RequestHeaders.Authorization -ne "Bearer test-token" -or $RequestTimeoutSeconds -ne 30) {
    throw "Authenticated artifact request arguments drifted"
  }
  [pscustomobject]@{
    StatusCode = 302
    Headers = @{ Location = 'https://productionresultssa10.blob.core.windows.net/actions-results/test.zip?sig=fixture' }
  }
}
$downloadRequest = {
  param([uri]$RequestUri, [string]$OutputPath, [int]$RequestTimeoutSeconds)
  $script:downloadCalls++
  if ($RequestUri.Host -ne 'productionresultssa10.blob.core.windows.net' -or $RequestUri.Query -ne '?sig=fixture') {
    throw "Signed artifact target was not forwarded"
  }
  if ($OutputPath -ne $destination -or $RequestTimeoutSeconds -ne 30) { throw "Artifact download arguments drifted" }
}
Save-GitHubArtifactArchive -ArchiveApiUri $archiveApiUri -Headers $headers -DestinationPath $destination -AuthenticatedRequestInvoker $authenticatedRequest -DownloadRequestInvoker $downloadRequest
if ($authenticatedCalls -ne 1 -or $downloadCalls -ne 1) { throw "Artifact download request count drifted" }

function Assert-ArtifactRedirectFailure {
  param([Parameter(Mandatory)][string]$ExpectedMessage, [Parameter(Mandatory)][scriptblock]$ResponseFactory)
  $script:blockedDownloadCalls = 0
  $blockedDownload = { $script:blockedDownloadCalls++ }
  try {
    Save-GitHubArtifactArchive -ArchiveApiUri $archiveApiUri -Headers $headers -DestinationPath $destination -AuthenticatedRequestInvoker $ResponseFactory -DownloadRequestInvoker $blockedDownload
  } catch {
    if ($_.Exception.Message -notlike "*$ExpectedMessage*") { throw }
    if ($script:blockedDownloadCalls -ne 0) { throw "Untrusted redirect reached the download request" }
    return
  }
  throw "Expected artifact redirect failure was not raised: $ExpectedMessage"
}

Assert-ArtifactRedirectFailure "expected redirect" {
  [pscustomobject]@{ StatusCode = 200; Headers = @{} }
}
Assert-ArtifactRedirectFailure "location is ambiguous" {
  [pscustomobject]@{ StatusCode = 302; Headers = @{ Location = @(
    'https://productionresultssa10.blob.core.windows.net/a.zip?sig=one',
    'https://productionresultssa10.blob.core.windows.net/b.zip?sig=two'
  ) } }
}
foreach ($untrustedLocation in @(
  'http://productionresultssa10.blob.core.windows.net/test.zip?sig=fixture',
  'https://evil.example/test.zip?sig=fixture',
  'https://productionresultssa10.blob.core.windows.net/test.txt?sig=fixture',
  'https://productionresultssa10.blob.core.windows.net/test.zip'
)) {
  Assert-ArtifactRedirectFailure "target is not trusted" {
    [pscustomobject]@{ StatusCode = 302; Headers = @{ Location = $untrustedLocation } }
  }
}

$regularEntry = [pscustomobject]@{ ExternalAttributes = -2119958496 }
Assert-GitHubArtifactZipEntryType -Entry $regularEntry -DisplayName "regular.json"

function Assert-ZipEntryTypeFailure {
  param([Parameter(Mandatory)][int]$ExternalAttributes)
  try {
    Assert-GitHubArtifactZipEntryType -Entry ([pscustomobject]@{ ExternalAttributes = $ExternalAttributes }) -DisplayName "unsafe-entry"
  } catch {
    if ($_.Exception.Message -notlike "*is not a regular file*") { throw }
    return
  }
  throw "Expected special ZIP entry to be rejected: $ExternalAttributes"
}

Assert-ZipEntryTypeFailure -ExternalAttributes -1577123840 # Unix symbolic link (0120777)
Assert-ZipEntryTypeFailure -ExternalAttributes 1106051088  # Unix directory plus DOS directory bit
Assert-ZipEntryTypeFailure -ExternalAttributes -2119957472 # Regular Unix mode plus DOS reparse-point bit

Write-Host "PASS: GitHub artifact download separates authentication from a trusted redirect and rejects special ZIP entries"

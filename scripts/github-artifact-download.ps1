function Assert-GitHubArtifactZipEntryType {
  param(
    [Parameter(Mandatory)]$Entry,
    [Parameter(Mandatory)][string]$DisplayName
  )

  $unixMode = (([int64]$Entry.ExternalAttributes -shr 16) -band 0xFFFF)
  $unixFileType = $unixMode -band 0xF000
  $dosAttributes = [int64]$Entry.ExternalAttributes -band 0xFFFF
  $unsafeDosAttributes = $dosAttributes -band 0x410
  if ($unixFileType -ne 0x8000 -or $unsafeDosAttributes -ne 0) {
    throw "AUDIT FAILED: GitHub artifact ZIP entry is not a regular file: $DisplayName"
  }
}

function Save-GitHubArtifactArchive {
  param(
    [Parameter(Mandatory)][uri]$ArchiveApiUri,
    [Parameter(Mandatory)][System.Collections.IDictionary]$Headers,
    [Parameter(Mandatory)][string]$DestinationPath,
    [ValidateRange(1, 120)][int]$TimeoutSeconds = 30,
    [scriptblock]$AuthenticatedRequestInvoker,
    [scriptblock]$DownloadRequestInvoker
  )

  if ($null -eq $AuthenticatedRequestInvoker) {
    $AuthenticatedRequestInvoker = {
      param([uri]$RequestUri, [System.Collections.IDictionary]$RequestHeaders, [int]$RequestTimeoutSeconds)
      try {
        return Invoke-WebRequest -Method Get -Uri $RequestUri -Headers $RequestHeaders -MaximumRedirection 0 -TimeoutSec $RequestTimeoutSeconds
      } catch {
        if ($null -eq $_.Exception.Response) { throw }
        return $_.Exception.Response
      }
    }
  }
  if ($null -eq $DownloadRequestInvoker) {
    $DownloadRequestInvoker = {
      param([uri]$RequestUri, [string]$OutputPath, [int]$RequestTimeoutSeconds)
      Invoke-WebRequest -Method Get -Uri $RequestUri -OutFile $OutputPath -MaximumRedirection 0 -TimeoutSec $RequestTimeoutSeconds
    }
  }

  $response = & $AuthenticatedRequestInvoker $ArchiveApiUri $Headers $TimeoutSeconds
  if ([int]$response.StatusCode -ne 302) {
    throw "AUDIT FAILED: GitHub artifact endpoint did not return the expected redirect"
  }
  $locations = @($response.Headers.Location)
  if ($locations.Count -ne 1) {
    throw "AUDIT FAILED: GitHub artifact redirect location is ambiguous"
  }

  $redirectUri = $null
  $isAbsolute = [uri]::TryCreate([string]$locations[0], [UriKind]::Absolute, [ref]$redirectUri)
  $isTrusted = $isAbsolute -and
    $redirectUri.Scheme -eq "https" -and
    $redirectUri.IsDefaultPort -and
    [string]::IsNullOrEmpty($redirectUri.UserInfo) -and
    $redirectUri.Host -match '^productionresults[a-z0-9-]*\.blob\.core\.windows\.net$' -and
    $redirectUri.AbsolutePath.EndsWith('.zip', [StringComparison]::OrdinalIgnoreCase) -and
    -not [string]::IsNullOrEmpty($redirectUri.Query) -and
    [string]::IsNullOrEmpty($redirectUri.Fragment)
  if (-not $isTrusted) {
    throw "AUDIT FAILED: GitHub artifact redirect target is not trusted"
  }

  & $DownloadRequestInvoker $redirectUri $DestinationPath $TimeoutSeconds
}

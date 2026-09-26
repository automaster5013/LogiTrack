function Invoke-GitHubGetAll {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][uri]$BaseUri,
    [Parameter(Mandatory)][System.Collections.IDictionary]$Headers,
    [ValidateRange(1, 100)][int]$MaximumPages = 100,
    [scriptblock]$RequestInvoker
  )

  if ($null -eq $RequestInvoker) {
    $RequestInvoker = {
      param([uri]$RequestUri, [System.Collections.IDictionary]$RequestHeaders)
      Invoke-WebRequest -Method Get -Uri $RequestUri -Headers $RequestHeaders
    }
  }

  if ($BaseUri.Scheme -ne "https" -or $BaseUri.Host -ne "api.github.com" -or -not $BaseUri.IsDefaultPort -or $BaseUri.UserInfo) {
    throw "AUDIT FAILED: GitHub API base URI is not trusted"
  }

  $items = @()
  $visitedUris = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  $separator = if ($Path.Contains("?")) { "&" } else { "?" }
  [uri]$uri = "$($BaseUri.AbsoluteUri.TrimEnd('/'))$Path${separator}per_page=100"
  $repositoryPathPrefix = "$($BaseUri.AbsolutePath.TrimEnd('/'))/"

  for ($page = 1; $page -le $MaximumPages; $page++) {
    if (-not $visitedUris.Add($uri.AbsoluteUri)) {
      throw "AUDIT FAILED: GitHub pagination repeated a page: $Path"
    }

    $response = & $RequestInvoker $uri $Headers
    $document = $null
    try {
      try {
        $document = [System.Text.Json.JsonDocument]::Parse([string]$response.Content)
      } catch {
        throw "AUDIT FAILED: GitHub pagination returned invalid JSON: $Path"
      }
      if ($document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Array) {
        throw "AUDIT FAILED: GitHub pagination response is not an array: $Path"
      }
      if ($document.RootElement.GetArrayLength() -gt 100) {
        throw "AUDIT FAILED: GitHub pagination response exceeded 100 items: $Path"
      }
    } finally {
      if ($null -ne $document) { $document.Dispose() }
    }
    $pageItems = @(($response.Content | ConvertFrom-Json) | Where-Object { $null -ne $_ })
    $items += $pageItems
    $link = @($response.Headers.Link) -join ","
    if ($link -notmatch '<([^>]+)>;\s*rel="next"') { return $items }

    $nextUri = $null
    $isAbsolute = [uri]::TryCreate($matches[1], [UriKind]::Absolute, [ref]$nextUri)
    $isTrusted = $isAbsolute -and
      $nextUri.Scheme -eq $BaseUri.Scheme -and
      $nextUri.Host -eq $BaseUri.Host -and
      $nextUri.Port -eq $BaseUri.Port -and
      $nextUri.UserInfo -eq $BaseUri.UserInfo -and
      $nextUri.AbsolutePath.StartsWith($repositoryPathPrefix, [StringComparison]::Ordinal)
    if (-not $isTrusted) {
      throw "AUDIT FAILED: GitHub pagination escaped the repository: $Path"
    }
    $uri = $nextUri
  }

  throw "AUDIT FAILED: GitHub pagination exceeded $MaximumPages pages: $Path"
}

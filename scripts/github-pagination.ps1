function ConvertFrom-GitHubQueryString {
  param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$Query,
    [Parameter(Mandatory)][string]$Path
  )

  $parameters = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
  foreach ($component in $Query.TrimStart('?').Split('&', [StringSplitOptions]::RemoveEmptyEntries)) {
    $separatorIndex = $component.IndexOf('=')
    $encodedName = if ($separatorIndex -ge 0) { $component.Substring(0, $separatorIndex) } else { $component }
    $encodedValue = if ($separatorIndex -ge 0) { $component.Substring($separatorIndex + 1) } else { "" }
    try {
      $name = [uri]::UnescapeDataString($encodedName.Replace('+', ' '))
      $value = [uri]::UnescapeDataString($encodedValue.Replace('+', ' '))
    } catch {
      throw "AUDIT FAILED: GitHub pagination query is invalid: $Path"
    }
    if ([string]::IsNullOrWhiteSpace($name) -or $parameters.ContainsKey($name)) {
      throw "AUDIT FAILED: GitHub pagination query is ambiguous: $Path"
    }
    $parameters[$name] = $value
  }
  return ,$parameters
}

function Invoke-GitHubGetAll {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][uri]$BaseUri,
    [Parameter(Mandatory)][System.Collections.IDictionary]$Headers,
    [ValidateRange(1, 100)][int]$MaximumPages = 100,
    [ValidateRange(1, 120)][int]$TimeoutSeconds = 30,
    [scriptblock]$RequestInvoker
  )

  if ($null -eq $RequestInvoker) {
    $RequestInvoker = {
      param([uri]$RequestUri, [System.Collections.IDictionary]$RequestHeaders, [int]$RequestTimeoutSeconds)
      Invoke-WebRequest -Method Get -Uri $RequestUri -Headers $RequestHeaders -MaximumRedirection 0 -TimeoutSec $RequestTimeoutSeconds
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
  $endpointPath = $uri.AbsolutePath
  $requiredQuery = ConvertFrom-GitHubQueryString -Query $uri.Query -Path $Path

  for ($page = 1; $page -le $MaximumPages; $page++) {
    if (-not $visitedUris.Add($uri.AbsoluteUri)) {
      throw "AUDIT FAILED: GitHub pagination repeated a page: $Path"
    }

    $response = & $RequestInvoker $uri $Headers $TimeoutSeconds
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
    $nextLinks = [regex]::Matches($link, '<([^>]+)>;\s*rel="next"')
    if ($nextLinks.Count -eq 0) { return $items }
    if ($nextLinks.Count -ne 1) {
      throw "AUDIT FAILED: GitHub pagination contains ambiguous next links: $Path"
    }

    $nextUri = $null
    $isAbsolute = [uri]::TryCreate($nextLinks[0].Groups[1].Value, [UriKind]::Absolute, [ref]$nextUri)
    $isTrusted = $isAbsolute -and
      $nextUri.Scheme -eq $BaseUri.Scheme -and
      $nextUri.Host -eq $BaseUri.Host -and
      $nextUri.Port -eq $BaseUri.Port -and
      $nextUri.UserInfo -eq $BaseUri.UserInfo -and
      $nextUri.AbsolutePath.StartsWith($repositoryPathPrefix, [StringComparison]::Ordinal)
    if (-not $isTrusted) {
      throw "AUDIT FAILED: GitHub pagination escaped the repository: $Path"
    }
    if ($nextUri.AbsolutePath -cne $endpointPath) {
      throw "AUDIT FAILED: GitHub pagination changed the endpoint: $Path"
    }
    $nextQuery = ConvertFrom-GitHubQueryString -Query $nextUri.Query -Path $Path
    foreach ($requiredName in $requiredQuery.Keys) {
      if (-not $nextQuery.ContainsKey($requiredName) -or $nextQuery[$requiredName] -cne $requiredQuery[$requiredName]) {
        throw "AUDIT FAILED: GitHub pagination changed a required query parameter: $Path"
      }
    }
    $uri = $nextUri
  }

  throw "AUDIT FAILED: GitHub pagination exceeded $MaximumPages pages: $Path"
}

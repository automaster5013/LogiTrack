function Assert-GitHubEvidenceJsonElement {
  param(
    [Parameter(Mandatory)][System.Text.Json.JsonElement]$Element,
    [Parameter(Mandatory)][string]$DisplayName
  )

  if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
    $propertyNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($property in $Element.EnumerateObject()) {
      if (-not $propertyNames.Add($property.Name)) {
        throw "AUDIT FAILED: GitHub evidence JSON contains a duplicate or case-conflicting property: $DisplayName"
      }
      Assert-GitHubEvidenceJsonElement -Element $property.Value -DisplayName $DisplayName
    }
  } elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
    foreach ($item in $Element.EnumerateArray()) {
      Assert-GitHubEvidenceJsonElement -Element $item -DisplayName $DisplayName
    }
  }
}

function ConvertFrom-GitHubEvidenceJson {
  param(
    [Parameter(Mandatory)][string]$Json,
    [Parameter(Mandatory)][string]$DisplayName,
    [ValidateRange(1, 100)][int]$MaximumDepth = 64
  )

  $options = [System.Text.Json.JsonDocumentOptions]::new()
  $options.AllowTrailingCommas = $false
  $options.CommentHandling = [System.Text.Json.JsonCommentHandling]::Disallow
  $options.MaxDepth = $MaximumDepth
  try {
    $document = [System.Text.Json.JsonDocument]::Parse($Json, $options)
  } catch {
    throw "AUDIT FAILED: GitHub evidence JSON is invalid or too deeply nested: $DisplayName"
  }
  try {
    Assert-GitHubEvidenceJsonElement -Element $document.RootElement -DisplayName $DisplayName
  } finally {
    $document.Dispose()
  }

  try {
    return $Json | ConvertFrom-Json -Depth $MaximumDepth
  } catch {
    throw "AUDIT FAILED: GitHub evidence JSON cannot be converted safely: $DisplayName"
  }
}

function Read-GitHubEvidenceJson {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$DisplayName,
    [ValidateRange(1, 10485760)][int]$MaximumBytes = 2097152,
    [ValidateRange(1, 100)][int]$MaximumDepth = 64
  )

  try {
    [byte[]]$bytes = [System.IO.File]::ReadAllBytes($Path)
  } catch {
    throw "AUDIT FAILED: GitHub evidence JSON cannot be read safely: $DisplayName"
  }
  if ($bytes.Length -lt 1 -or $bytes.Length -gt $MaximumBytes) {
    throw "AUDIT FAILED: GitHub evidence JSON byte size is invalid: $DisplayName"
  }
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "AUDIT FAILED: GitHub evidence JSON contains a UTF-8 byte-order mark: $DisplayName"
  }

  $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
  try {
    $json = $strictUtf8.GetString($bytes)
  } catch {
    throw "AUDIT FAILED: GitHub evidence JSON is not valid UTF-8: $DisplayName"
  }
  return ConvertFrom-GitHubEvidenceJson -Json $json -DisplayName $DisplayName -MaximumDepth $MaximumDepth
}

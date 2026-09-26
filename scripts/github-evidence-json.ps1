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

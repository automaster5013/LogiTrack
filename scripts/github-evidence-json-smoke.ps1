$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "github-evidence-json.ps1")

$valid = ConvertFrom-GitHubEvidenceJson -Json '{"digest":"sha256:test","nested":{"values":[1,true,null]}}' -DisplayName "valid.json"
if ($valid.digest -ne "sha256:test" -or $valid.nested.values.Count -ne 3) {
  throw "Valid GitHub evidence JSON was not converted correctly"
}

function Assert-EvidenceJsonFailure {
  param(
    [Parameter(Mandatory)][string]$Json,
    [Parameter(Mandatory)][string]$ExpectedMessage
  )
  try {
    ConvertFrom-GitHubEvidenceJson -Json $Json -DisplayName "unsafe.json" | Out-Null
  } catch {
    if ($_.Exception.Message -notlike "*$ExpectedMessage*") { throw }
    return
  }
  throw "Expected strict GitHub evidence JSON failure was not raised: $ExpectedMessage"
}

Assert-EvidenceJsonFailure -Json '{"digest":"trusted","digest":"conflicting"}' -ExpectedMessage "duplicate or case-conflicting property"
Assert-EvidenceJsonFailure -Json '{"digest":"trusted","Digest":"conflicting"}' -ExpectedMessage "duplicate or case-conflicting property"
Assert-EvidenceJsonFailure -Json '{"digest":"trusted",}' -ExpectedMessage "invalid or too deeply nested"
Assert-EvidenceJsonFailure -Json '{/*comment*/"digest":"trusted"}' -ExpectedMessage "invalid or too deeply nested"
$tooDeep = ('{"value":' * 65) + 'null' + ('}' * 65)
Assert-EvidenceJsonFailure -Json $tooDeep -ExpectedMessage "invalid or too deeply nested"

Write-Host "PASS: GitHub evidence JSON rejects ambiguous syntax, property collisions, and excessive nesting"

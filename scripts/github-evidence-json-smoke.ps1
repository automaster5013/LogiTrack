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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "github-evidence-json-smoke-$([guid]::NewGuid().ToString('N'))"
try {
  New-Item -ItemType Directory -Path $tempRoot | Out-Null
  $validPath = Join-Path $tempRoot "valid.json"
  $invalidUtf8Path = Join-Path $tempRoot "invalid-utf8.json"
  $bomPath = Join-Path $tempRoot "bom.json"
  $emptyPath = Join-Path $tempRoot "empty.json"
  [byte[]]$validBytes = [System.Text.UTF8Encoding]::new($false).GetBytes('{"digest":"sha256:file"}')
  [System.IO.File]::WriteAllBytes($validPath, $validBytes)
  [System.IO.File]::WriteAllBytes($invalidUtf8Path, [byte[]](0x7B, 0x22, 0x78, 0x22, 0x3A, 0x22, 0xC3, 0x28, 0x22, 0x7D))
  [System.IO.File]::WriteAllBytes($bomPath, [byte[]](@(0xEF, 0xBB, 0xBF) + $validBytes))
  [System.IO.File]::WriteAllBytes($emptyPath, [byte[]]@())

  $validFile = Read-GitHubEvidenceJson -Path $validPath -DisplayName "valid.json"
  if ($validFile.digest -ne "sha256:file") { throw "Valid UTF-8 evidence file was not converted correctly" }

  function Assert-EvidenceFileFailure {
    param(
      [Parameter(Mandatory)][string]$Path,
      [Parameter(Mandatory)][string]$ExpectedMessage,
      [int]$MaximumBytes = 2097152
    )
    try {
      Read-GitHubEvidenceJson -Path $Path -DisplayName "unsafe-file.json" -MaximumBytes $MaximumBytes | Out-Null
    } catch {
      if ($_.Exception.Message -notlike "*$ExpectedMessage*") { throw }
      return
    }
    throw "Expected GitHub evidence file failure was not raised: $ExpectedMessage"
  }

  Assert-EvidenceFileFailure -Path $invalidUtf8Path -ExpectedMessage "is not valid UTF-8"
  Assert-EvidenceFileFailure -Path $bomPath -ExpectedMessage "contains a UTF-8 byte-order mark"
  Assert-EvidenceFileFailure -Path $emptyPath -ExpectedMessage "byte size is invalid"
  Assert-EvidenceFileFailure -Path $validPath -MaximumBytes 8 -ExpectedMessage "byte size is invalid"
} finally {
  if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

Write-Host "PASS: GitHub evidence JSON rejects invalid UTF-8, BOMs, unsafe sizes, ambiguous syntax, property collisions, and excessive nesting"

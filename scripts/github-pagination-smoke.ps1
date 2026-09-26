$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "github-pagination.ps1")

$baseUri = [uri]"https://api.github.com/repos/automaster5013/LogiTrack"
$headers = @{ Accept = "application/vnd.github+json" }

$responses = [System.Collections.Generic.Queue[object]]::new()
$responses.Enqueue([pscustomobject]@{
  Content = '[{"number":1}]'
  Headers = @{ Link = '<https://api.github.com/repos/automaster5013/LogiTrack/dependabot/alerts?state=open&per_page=100&after=cursor>; rel="next"' }
})
$responses.Enqueue([pscustomobject]@{
  Content = '[{"number":2}]'
  Headers = @{}
})
$requestCount = 0
$request = {
  param([uri]$RequestUri, [System.Collections.IDictionary]$RequestHeaders)
  $script:requestCount++
  if ($RequestHeaders.Accept -ne "application/vnd.github+json") { throw "Headers were not forwarded" }
  return $responses.Dequeue()
}
$items = @(Invoke-GitHubGetAll -Path "/dependabot/alerts?state=open" -BaseUri $baseUri -Headers $headers -RequestInvoker $request)
if ($requestCount -ne 2 -or ($items.number -join ",") -ne "1,2") {
  throw "Pagination did not aggregate both pages"
}

function Assert-PaginationFailure {
  param(
    [Parameter(Mandatory)][string]$ExpectedMessage,
    [Parameter(Mandatory)][scriptblock]$Invoker
  )
  try {
    & $Invoker
  } catch {
    if ($_.Exception.Message -notlike "*$ExpectedMessage*") { throw }
    return
  }
  throw "Expected pagination failure was not raised: $ExpectedMessage"
}

$offRepositoryRequest = {
  [pscustomobject]@{
    Content = '[]'
    Headers = @{ Link = '<https://api.github.com/repos/another-owner/another-repo/dependabot/alerts?per_page=100>; rel="next"' }
  }
}
Assert-PaginationFailure "escaped the repository" {
  Invoke-GitHubGetAll -Path "/dependabot/alerts?state=open" -BaseUri $baseUri -Headers $headers -RequestInvoker $offRepositoryRequest
}

$changedEndpointRequest = {
  [pscustomobject]@{
    Content = '[]'
    Headers = @{ Link = '<https://api.github.com/repos/automaster5013/LogiTrack/issues?state=open&per_page=100&page=2>; rel="next"' }
  }
}
Assert-PaginationFailure "changed the endpoint" {
  Invoke-GitHubGetAll -Path "/dependabot/alerts?state=open" -BaseUri $baseUri -Headers $headers -RequestInvoker $changedEndpointRequest
}

$changedFilterRequest = {
  [pscustomobject]@{
    Content = '[]'
    Headers = @{ Link = '<https://api.github.com/repos/automaster5013/LogiTrack/dependabot/alerts?state=dismissed&per_page=100&page=2>; rel="next"' }
  }
}
Assert-PaginationFailure "changed a required query parameter" {
  Invoke-GitHubGetAll -Path "/dependabot/alerts?state=open" -BaseUri $baseUri -Headers $headers -RequestInvoker $changedFilterRequest
}

$changedQueryCaseRequest = {
  [pscustomobject]@{
    Content = '[]'
    Headers = @{ Link = '<https://api.github.com/repos/automaster5013/LogiTrack/dependabot/alerts?STATE=open&per_page=100&page=2>; rel="next"' }
  }
}
Assert-PaginationFailure "changed a required query parameter" {
  Invoke-GitHubGetAll -Path "/dependabot/alerts?state=open" -BaseUri $baseUri -Headers $headers -RequestInvoker $changedQueryCaseRequest
}

$ambiguousNextRequest = {
  [pscustomobject]@{
    Content = '[]'
    Headers = @{ Link = @(
      '<https://api.github.com/repos/automaster5013/LogiTrack/dependabot/alerts?state=open&per_page=100&page=2>; rel="next"',
      '<https://api.github.com/repos/automaster5013/LogiTrack/dependabot/alerts?state=open&per_page=100&page=3>; rel="next"'
    ) }
  }
}
Assert-PaginationFailure "contains ambiguous next links" {
  Invoke-GitHubGetAll -Path "/dependabot/alerts?state=open" -BaseUri $baseUri -Headers $headers -RequestInvoker $ambiguousNextRequest
}

$ambiguousQueryRequest = {
  [pscustomobject]@{
    Content = '[]'
    Headers = @{ Link = '<https://api.github.com/repos/automaster5013/LogiTrack/dependabot/alerts?state=open&state=dismissed&per_page=100&page=2>; rel="next"' }
  }
}
Assert-PaginationFailure "query is ambiguous" {
  Invoke-GitHubGetAll -Path "/dependabot/alerts?state=open" -BaseUri $baseUri -Headers $headers -RequestInvoker $ambiguousQueryRequest
}

$repeatedUri = "$($baseUri.AbsoluteUri)/dependabot/alerts?state=open&per_page=100"
$cycleRequestCount = 0
$cycleRequest = {
  $script:cycleRequestCount++
  [pscustomobject]@{ Content = '[]'; Headers = @{ Link = "<$repeatedUri>; rel=`"next`"" } }
}
Assert-PaginationFailure "repeated a page" {
  Invoke-GitHubGetAll -Path "/dependabot/alerts?state=open" -BaseUri $baseUri -Headers $headers -RequestInvoker $cycleRequest
}
if ($cycleRequestCount -ne 1) { throw "Repeated page was requested more than once" }

$invalidJsonRequest = {
  [pscustomobject]@{ Content = 'not-json'; Headers = @{} }
}
Assert-PaginationFailure "returned invalid JSON" {
  Invoke-GitHubGetAll -Path "/dependabot/alerts?state=open" -BaseUri $baseUri -Headers $headers -RequestInvoker $invalidJsonRequest
}

$objectResponseRequest = {
  [pscustomobject]@{ Content = '{"number":1}'; Headers = @{} }
}
Assert-PaginationFailure "response is not an array" {
  Invoke-GitHubGetAll -Path "/dependabot/alerts?state=open" -BaseUri $baseUri -Headers $headers -RequestInvoker $objectResponseRequest
}

$oversizedContent = "[" + ((1..101) -join ",") + "]"
$oversizedResponseRequest = {
  [pscustomobject]@{ Content = $oversizedContent; Headers = @{} }
}
Assert-PaginationFailure "response exceeded 100 items" {
  Invoke-GitHubGetAll -Path "/dependabot/alerts?state=open" -BaseUri $baseUri -Headers $headers -RequestInvoker $oversizedResponseRequest
}

$boundedPage = 0
$boundedRequest = {
  $script:boundedPage++
  [pscustomobject]@{
    Content = '[]'
    Headers = @{ Link = "<$($baseUri.AbsoluteUri)/dependabot/alerts?state=open&per_page=100&after=$boundedPage>; rel=`"next`"" }
  }
}
Assert-PaginationFailure "exceeded 2 pages" {
  Invoke-GitHubGetAll -Path "/dependabot/alerts?state=open" -BaseUri $baseUri -Headers $headers -MaximumPages 2 -RequestInvoker $boundedRequest
}
if ($boundedPage -ne 2) { throw "Pagination page limit was not enforced" }

Write-Host "PASS: GitHub pagination preserves one trusted endpoint and query across bounded array pages"

$ErrorActionPreference = "Stop"

docker run --rm `
  -v "${PWD}\api:/app" `
  -v logitrack-maven-cache:/root/.m2 `
  -w /app `
  maven:3.9.11-eclipse-temurin-21@sha256:6fdc855a6ed81d288ca7ca37ac6ff5e9308b612485c0801d70b25a858c83d237 `
  mvn -q verify

if ($LASTEXITCODE -ne 0) { throw "API tests or the 80% domain coverage gate failed" }

Write-Host "PASS: API tests and domain line/branch coverage are at least 80%"

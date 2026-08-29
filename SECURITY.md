# Security Policy

## Reporting a Vulnerability

Please report security vulnerabilities using GitHub's
[private vulnerability reporting](https://github.com/katekruger/pipeline-waterfall/security/advisories/new),
not by email or public issue. This keeps the report confidential until a fix
is available.

You should expect an initial response within a few days. This is a solo-
maintained open-source project, not a commercial product with an SLA — please
be patient.

## Scope

This is a dbt package: SQL models, macros, and seeds that run inside a user's
own warehouse. There is no hosted service, API, or infrastructure operated by
this project. Relevant reports include things like SQL that could be made to
behave unexpectedly via crafted `var` input, or CI/workflow configuration
issues (see `.github/workflows/zizmor.yml`).

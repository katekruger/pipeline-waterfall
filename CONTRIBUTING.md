# Contributing

Thanks for considering a contribution to `pipeline_waterfall`.

## Setup

```bash
git clone https://github.com/katekruger/pipeline-waterfall
cd pipeline-waterfall/integration_tests
uv run --with-requirements requirements.txt dbt deps
uv run --with-requirements requirements.txt dbt build
```

`dbt build` runs against DuckDB using the seeded fixtures in `integration_tests/seeds/` —
no Salesforce, HubSpot, or dbt Cloud account needed.

Every model needs a description in `models/schema.yml`. Every contested
definition (pushed vs. slipped, cohort-at-open vs. current-state, etc.) is a
`var`, never a hardcoded house opinion — see [AGENTS.md](AGENTS.md) for the
full list of non-negotiables.

## Use of AI

AI-assisted contributions are welcome. Disclose it in the PR: which model,
which harness (Claude Code, Cursor, Copilot, etc.). This isn't a gate on
acceptance — the same review bar applies either way — it's just honesty about
provenance, especially for anything touching the movement-classification
rules, where getting the *definition* right matters more than the SQL.

## What gets rejected

- A new movement-classification rule or preflight test with no fixture
  proving it fires (and, for preflight tests, no deliberately-broken fixture
  proving it fails correctly).
- Hardcoding a definition that BUILD-PLAN.md documents as contested (e.g.
  picking "pushed" or "slipped" as the only definition) instead of exposing
  it as a `var` with both options documented.
- Reformatting or restyling code unrelated to the change.
- New dependencies without a one-line justification in the PR body.
- Removing or weakening a test (especially `bridge_reconciles`) to make CI
  pass.
- Direct commits to `main`.

# pipeline-waterfall

[![CI](https://github.com/katekruger/pipeline-waterfall/actions/workflows/ci.yml/badge.svg)](https://github.com/katekruger/pipeline-waterfall/actions/workflows/ci.yml)
![dbt](https://img.shields.io/badge/dbt-%3E%3D1.10.0%2C%3C3.0.0-orange)
![license](https://img.shields.io/badge/license-Apache%202.0-blue)

The movement layer that turns CRM history into a reconciling pipeline bridge, without telling you what "slipped" means.

## Status

**Pre-alpha, Salesforce only.** The contract, movement classification, and the full reconciliation/preflight suite are built and tested. Docs and the v0.1.0 release are landing now; HubSpot, multi-currency conversion, and fiscal periods are not built yet (v0.2+ — see `BUILD-PLAN.md`).

**Before you install this, you need:**

- `fivetran/dbt_salesforce` v2.4.1+ with `salesforce__opportunity_history_enabled: true` set — that model is disabled by default.
- **At least two full periods of history already synced.** Fivetran History Mode does not backfill — a connection switched into history mode today has zero usable history today. `history_depth` will fail your build loudly rather than let you run a waterfall against a window you don't actually have data for.

If either of those isn't true yet, this package will tell you exactly that the first time you run it, rather than produce a number that happens to be wrong.

## Quick start

```yaml
# packages.yml
packages:
  - package: katekruger/pipeline_waterfall
    version: [">=0.1.0", "<0.2.0"]
```

```yaml
# dbt_project.yml
vars:
  salesforce__opportunity_history_enabled: true   # fivetran/dbt_salesforce's own var
  waterfall__amount_column: 'amount'              # or a custom ARR field
```

Copy `seeds/waterfall_stage_order.csv` into your own project's `seeds/` and edit it to match your actual stage names, in the order deals move through them — this package has no way to know your stage taxonomy, and `stage_order_complete` will tell you exactly which observed stages are missing from it.

```bash
dbt deps
dbt build
```

## The ten buckets

Evaluated per opportunity, comparing state at period start (t0) to period end (t1). Precedence — this is load-bearing — is terminal (`won`/`lost`) > `reopened` > date movement (`pushed`/`pulled_in`/`slipped`) > `advanced` > amount movement (`expanded`/`contracted`).

| Bucket | Rule |
|---|---|
| `created` | absent at t0, present and open at t1, created within the period |
| `won` | not won at t0 (or didn't exist), won at t1 |
| `lost` | not closed at t0 (or didn't exist), closed-lost at t1 |
| `reopened` | closed at t0, open again at t1 — never folded into `created` |
| `pushed` | open at both, close date moved to a later period |
| `pulled_in` | open at both, close date moved to an earlier period — the mirror of `pushed`, required for the bridge to reconcile |
| `slipped` | close date was in-period at t0, still open at t1 |
| `advanced` | open at both, stage order increased, close date unchanged |
| `expanded` | open at both, amount increased |
| `contracted` | open at both, amount decreased |

Every bucket carries both a count and a dollar figure — "three large deals slipped" and "forty small deals slipped" can be the same percentage and demand opposite responses. Full definitions, including where practitioners genuinely disagree, are in [`docs/definitions.md`](docs/definitions.md).

## Configuration

Every contested definition is a variable, with every option documented and the consequence of each spelled out — never a hardcoded house opinion. Full detail in [`docs/definitions.md`](docs/definitions.md); this is the quick-reference version.

| Variable | Default | Options |
|---|---|---|
| `waterfall__history_source` | `'fivetran_salesforce_history'` | Salesforce only in v0.1 — other values raise a clear error |
| `waterfall__amount_column` | `'amount'` | any numeric column on the source model, e.g. a custom ARR field |
| `waterfall__stage_order_seed` | `'waterfall_stage_order'` | the name of your own stage-order seed |
| `waterfall__cohort_mode` | `'cohort_at_open'` | `'current_state'` |
| `waterfall__created_stage_filter` | `[]` (all opportunities) | a list of stage names |
| `waterfall__slippage_definition` | `'close_date_period'` | `'period_end_open'` |
| `waterfall__amount_change_precedence` | `'terminal_wins'` | `'movement_wins'` |
| `waterfall__period_grain` | `['month', 'quarter']` | any subset |
| `waterfall__min_history_periods` | `2` | any integer — the `history_depth` threshold |
| `waterfall__currency_mode` | unset | any value acknowledges multi-currency data; does not convert (v0.2) |

## What this refuses to do

A truly out-of-the-box CRM waterfall is not achievable — every available history source is either disabled by default, not backfilled, capped at 20 tracked fields, or missing the close-date field entirely. Most internal implementations don't know this and don't reconcile, and nobody notices until a board meeting.

This package would rather fail your build than hand you a wrong number quietly. Seven checks run every time and fail loudly, each naming the exact fix:

- **`bridge_reconciles`** — opening pipeline + every movement bucket must equal closing pipeline, *exactly*, every period. This is the headline feature; if it doesn't hold, nothing downstream can be trusted.
- **`hubspot_closedate_tracked`** — the single most important check in the package (once HubSpot lands in v0.2). HubSpot doesn't track close date in property history by default. Without it, a waterfall runs cleanly, reconciles, and reports zero slippage forever — and nothing else would ever tell you why.
- **`salesforce_history_enabled`**, **`history_depth`** — the models this package reads from are disabled by default and don't backfill. A new connection has zero usable history on day one.
- **`stage_order_complete`** — a stage missing from your stage-order seed doesn't error, it just quietly stops advancing.
- **`multi_currency_unguarded`** — Fivetran's Salesforce package has zero currency handling. Multi-currency orgs are being summed across currencies right now, and nobody else catches this.
- **`history_gap`** — a known bug in older Fivetran versions drops individual days from history. Silently missing a day looks identical to "nothing happened."

Every one of these has been proven to actually fire against a deliberately broken scenario, not just written to look like it would — see `docs/decisions/0004-pipeline-definition-and-preflight-architecture.md`.

## Documentation

- [`docs/definitions.md`](docs/definitions.md) — every contested definition, both options, and the consequence of each. The document to forward to whoever needs to trust the number.
- [`docs/history-sources.md`](docs/history-sources.md) — every history source and its specific failure mode.
- [`BUILD-PLAN.md`](BUILD-PLAN.md) — the full architecture, roadmap, and research behind the package.
- [`docs/decisions/`](docs/decisions/) — ADRs for every non-obvious, hard-to-reverse decision.

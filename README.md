# pipeline-waterfall

The movement layer that turns CRM history into a reconciling pipeline bridge, without telling you what "slipped" means.

**Status: pre-alpha.** The history contract, movement classification, and reconciliation/preflight suite are in place; docs and the v0.1 release are still being built. Not ready to install yet — see [BUILD-PLAN.md](BUILD-PLAN.md) for the roadmap.

Full docs, a real quick start, and the ten movement buckets will land here as v0.1 comes together.

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

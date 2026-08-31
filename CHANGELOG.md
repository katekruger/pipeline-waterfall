# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

## 0.1.1 — 2026-08-31

### Fixed

- `waterfall__bridge_monthly` and `waterfall__bridge_quarterly` now expose `bridge_amount`, the column that actually reconciles opening pipeline to closing pipeline. `movement_amount` is still there for business reporting, but it is not the column to chart -- `bridge_amount` is. See ADR 0005.
- A new preflight test, `assert_fixture_classification`, checks every fixture entity against its expected movement bucket. A misclassification -- e.g. a deal that should land in `expanded` landing in `slipped` instead -- now fails the build instead of passing silently as long as the totals still reconcile.
- `slipped` no longer swallows deals that advanced a stage or changed amount within the period, as long as their close date held. A deal that grew in-period without its close date moving is now reported as `expanded`, not a slip. See ADR 0006.
- `waterfall__created_stage_filter` now fails the build with a message naming the entity, amount, and excluded stage whenever the configured filter would break reconciliation, instead of silently producing a bridge that doesn't tie out. See ADR 0008.
- Fixtures now span two full quarters instead of one, so quarterly-grain reporting is exercised against real data rather than passing by coincidence. See ADR 0009.
- `dbt compile` and `dbt docs generate` now succeed against a completely empty (cold) warehouse, including under `waterfall__cohort_mode: current_state`. See ADR 0007 and ADR 0010.
- `waterfall__movement_detail`'s previously-undocumented columns (`entity_id`, `source_relation`, `period_grain`, `period_start`, `period_end`, `stage`, `currency_code`) now have schema.yml descriptions, completing column coverage for every model a user is expected to query directly.

## 0.1.0 — 2026-08-29

### Added

- The daily-state contract (`int_waterfall__daily_state`), normalizing CRM opportunity history into one source-agnostic grain that everything downstream reads from.
- A Salesforce history adapter for `fivetran/dbt_salesforce`, including support for a custom ARR/amount column and opportunistic multi-currency passthrough.
- Movement classification into ten buckets — created, won, lost, reopened, pushed, pulled_in, slipped, advanced, expanded, contracted — each with both a count and a dollar figure, at monthly and quarterly grain.
- `bridge_reconciles`, the headline test: opening pipeline plus every movement bucket equals closing pipeline, exactly, every period.
- Six more preflight checks that fail the build instead of letting a wrong number ship silently: `history_depth`, `hubspot_closedate_tracked`, `salesforce_history_enabled`, `stage_order_complete`, `multi_currency_unguarded`, and `history_gap`.
- Ten configurable variables covering every contested definition in the package — cohort mode, slippage definition, amount-change precedence, created-stage filter, and more — with both options documented and no hardcoded house opinion.
- `docs/definitions.md` and `docs/history-sources.md`, documenting every contested definition and every history source's specific failure mode.

### Internal

- dbt package scaffolding, CI (`dbt build` on DuckDB, plus a `zizmor` Actions security audit), a tag-triggered release workflow, and four ADRs recording the non-obvious decisions behind the classifier and the bridge math.

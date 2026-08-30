# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Fixed

- `waterfall__created_stage_filter` breaking `bridge_reconciles` with no explanation why -- a new preflight test, `created_stage_filter_excludes_pipeline`, now names the excluded entity, stage, and amount at stake whenever this happens, and the README warns about it directly. This is a named refusal, not a full fix: the var remains unsafe to use with a filter that excludes any stage a still-open entity is created in. See ADR 0008.
- `dbt compile` and `dbt docs generate` no longer fail against a cold/empty warehouse -- the compile-time `run_query()` calls used to resolve period boundaries and `waterfall__cohort_mode: current_state`'s "latest known snapshot" date are now guarded against a relation that hasn't been built yet, not just against pure static parsing. `waterfall__cohort_mode: current_state` also now reconciles across repeated `dbt build` runs, including this package's own unit tests. Both are covered in CI going forward. See ADR 0007.
- `slipped` no longer swallows `advanced`/`expanded`/`contracted` for any deal whose close date simply falls within the reporting period -- previously true of most of a current-quarter pipeline review. `slipped` now additionally requires that stage and amount are both unchanged; a deal that also advanced a stage or moved dollars is now reported as that instead. See ADR 0006.
- `waterfall__bridge_monthly` and `waterfall__bridge_quarterly` now expose `bridge_amount`, the actual reconciling column -- previously they only aggregated `movement_amount`, a business-reporting figure with no reconciling property, so a chart built from the model literally named `bridge_monthly` never tied out. A new preflight test, `mart_bridge_reconciles`, fails the build if this regresses. See ADR 0005.

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

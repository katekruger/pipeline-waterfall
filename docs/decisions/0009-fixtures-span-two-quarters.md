---
status: accepted
date: 2026-08-30
decision-makers: Kate Kruger
---

# The integration fixtures must span real quarter boundaries

## Context and Problem Statement

An external audit (ENG-7e, item 1, 30 Aug 2026) found that
`integration_tests/seeds/salesforce__opportunity_daily_history.csv` spanned
exactly one real month (2026-01-01 -> 2026-02-01, over 5 distinct
`date_day` values). `waterfall__period_grain` defaults to
`['month', 'quarter']` -- quarterly grain, half the shipped surface area,
had never once run against real data. Investigating turned up a second,
more direct cause than the fixture span alone:
`integration_tests/dbt_project.yml` explicitly overrode
`waterfall__period_grain` to `['month']` only, with a comment recording
that this was a deliberate choice made specifically to avoid "bloating the
seed" with quarter-spanning history. That override, not just the fixture
span, is why quarter grain was silently untested in every CI run to date
-- extending the fixture span alone would not have surfaced quarter-grain
rows at all without also removing it.

## Decision Drivers

- BUILD-PLAN.md §9, M6: "CI green on DuckDB" is supposed to mean the
  shipped surface area actually ran, not that half of it silently built
  zero rows every time.
- AGENTS.md rule 2: "Tests before implementation" / "a preflight test
  you haven't seen fail is not tested" -- the same standard applies to a
  grain that's never been seen to produce a single row.
- The original override's own reasoning (recorded in its comment) was
  sound *at the time*: backfilling every fixture with months of
  unchanging history "just to satisfy one grain's threshold" was
  correctly judged not worth it when nothing else needed that span. ENG-7e
  changes the cost-benefit: quarterly correctness is now a specific,
  named gap that needs closing, not a hypothetical one.

## Considered Options

- Extend the fixture span without removing the `waterfall__period_grain`
  override. Rejected -- confirmed by testing: quarter periods still
  generate zero rows, since the harness's own project vars silently drop
  `'quarter'` from the grain list regardless of what the seed contains.
- Remove the override and extend the fixture span together, adding new
  monthly anchor snapshots (not just quarter-boundary ones) for every
  existing entity so every monthly period from January through June
  remains fully populated too. (Chosen.)
- Remove the override only, without extending the fixture -- accept that
  quarter periods would still be dropped by `int_waterfall__period_boundaries`
  (their `period_end` would exceed `max_date`) since the only real data
  the seed has is January/February. Rejected -- this proves nothing;
  quarter grain would build cleanly and still be empty, which is exactly
  the previously-undetected failure mode.

## Decision Outcome

Chosen option. `waterfall__period_grain`'s override in
`integration_tests/dbt_project.yml` is removed entirely, and the seed
gains flat, unchanging snapshot rows at `2026-03-01`, `2026-04-01`,
`2026-05-01`, `2026-06-01`, and `2026-07-01` for every existing entity --
each identical to that entity's final (`2026-02-01`) state, since nothing
new needs to happen in those months for the 20 original fixtures to keep
proving what they already prove. This intentionally makes *every* monthly
period from January through June complete and reconciling too (not just
the two new quarters), because `int_waterfall__period_boundaries` derives
periods for every configured grain from the same global `min(date_day)` /
`max(date_day)` -- extending `max_date` to satisfy quarter grain
unavoidably extends monthly grain's own period list, and every one of
those new monthly periods needs real, consistent data at its boundaries
or it reproduces the exact "vanished entity" failure mode
`bridge_reconciles`'s own unit test exists to catch.

A new fixture, `case23-quarter-only-expansion-1`, is added specifically to
prove quarter-grain classification is genuine rather than incidental: it
sits flat at `10000` through `2026-03-01`, jumps to `18000` at
`2026-04-01`, and stays flat afterward -- so it has no analogous movement
in *any* single monthly period (flat within every month), and only
classifies as `expanded` when the quarter's own `t0`/`t1` snapshots
(`2026-01-01` vs `2026-04-01`) are compared directly.

`waterfall__min_history_periods`'s pre-existing test-harness override (`1`,
vs. the package default `2`) is left as-is -- it addresses a different,
still-true constraint (the fixture set is still deliberately sparse in
its early history, not continuous daily rows) unrelated to this decision.

### Consequences

- Good, because `waterfall__bridge_quarterly`, `mart_bridge_reconciles`,
  and `bridge_reconciles` now all run against two real, non-empty
  quarterly periods (`2026-01-01`/`2026-04-01`) and reconcile --
  previously true only by vacuous emptiness.
- Good, because a new integration test
  (`integration_tests/tests/assert_quarterly_boundary_classification.sql`)
  makes the quarter-specific reconciliation claim and the boundary-crossing
  classification claim explicit, not just incidentally implied by the
  generic per-grain checks.
- Bad, because the seed file roughly triples in row count (46 -> 163
  rows) for what is mostly repetitive, unchanging data -- a real cost the
  original override was written specifically to avoid. Judged worth it
  here because the alternative is an entire grain shipping with zero
  test coverage.

## Assumption this relies on

Nothing else in the fixture set depends on monthly periods stopping at
February -- confirmed by running the full existing test suite
(`assert_fixture_classification`, `assert_precedence_cases_12_13`, all
unit tests) unchanged against the extended seed before adding anything
new, with zero regressions.

## Known limitation

This does not add coverage for a period that starts mid-history (the
`history_depth` preflight's own concern) or for fiscal periods (v0.2,
BUILD-PLAN.md §3) -- both remain untested by this fixture set. It also
does not test a quarter boundary that a monthly period's own June-crossing
data would disagree with in some more adversarial way (e.g. a deal that
moves stage AND date AND amount differently within different months of
the same quarter) -- `case23` isolates a single dimension (amount) for
clarity; a more adversarial multi-month-vs-quarter fixture is a candidate
for a future PR if quarter-grain edge cases turn out to need more
coverage.

## Confirmation

Before this fix: `int_waterfall__period_boundaries` produced only
`period_grain = 'month'` rows (confirmed via direct query), regardless of
the seed's date span, because of the harness's own var override.
Removing the override alone (fixture unchanged) was not tested in
isolation since the fixture extension was designed and applied together;
after both changes, `int_waterfall__period_boundaries` produces two
`period_grain = 'quarter'` rows (`2026-01-01`/`2026-04-01` and
`2026-04-01`/`2026-07-01`), `waterfall__bridge_quarterly` is non-empty and
reconciles, and `case23-quarter-only-expansion-1` classifies as `expanded`
for the first quarter with no analogous monthly-grain row.

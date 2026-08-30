---
status: accepted
date: 2026-08-30
decision-makers: Kate Kruger
---

# waterfall__movement_detail must not incrementally append under current_state

## Context and Problem Statement

CI on PR #9 (opened to fix a broken workflow file from PR #8) caught a
real ENG-7b failure that this series' own ADR 0007 had incorrectly
concluded didn't reproduce: running the default `dbt build` (implicitly
`waterfall__cohort_mode: cohort_at_open`) and then, on that same
already-populated database, running `dbt build --vars
'{waterfall__cohort_mode: current_state}'` fails `bridge_reconciles` and
`mart_bridge_reconciles` with real (non-zero) deltas -- not the compile
error ADR 0007 fixed, a genuine reconciliation mismatch.

Root cause: `waterfall__movement_detail` is `materialized = 'incremental'`
with an append-only filter -- `where period_start > max(period_start
already loaded)`. That filter is correct under `cohort_at_open`: once a
period's `t0`/`t1` boundaries are both fixed calendar dates, its
classification never changes on a later run, so only genuinely new
periods ever need a new row. It is wrong under `current_state`: every
period's `t1` is defined as "the single latest known snapshot," which
moves forward on every sync -- so a period computed on an earlier run
under `current_state` is not merely incomplete, its stored
`movement_bucket`/`bridge_amount` are actively stale relative to what
`current_state` means *right now*. The append-only filter has no
mechanism to notice this and never re-selects an already-loaded
`period_start`, so `waterfall__movement_detail` kept reporting bridge
amounts computed against the wrong "latest date," while
`bridge_reconciles`/`mart_bridge_reconciles` (both plain views) correctly
recomputed opening/closing pipeline against the CURRENT "latest date" on
every run. The two sides of the bridge equation were being computed
against two different snapshots.

## Decision Drivers

- Same as ADR 0007: a documented config option that reconciles once and
  silently diverges afterward is worse than not offering it.
- `bridge_reconciles` must not be weakened (this remediation's own ground
  rules) -- the fix has to make the underlying data consistent, not
  loosen the check that caught it.
- Whatever fix is chosen must not regress `cohort_at_open`'s existing,
  correct incremental behavior -- most users will never touch
  `current_state`.

## Considered Options

- Full-refresh `waterfall__movement_detail` (and cascade to anything
  depending on it) automatically whenever `waterfall__cohort_mode` differs
  from the value used to build the existing relation. Rejected -- dbt has
  no supported way to detect "the var changed since last run" from inside
  a model; would need external state tracking outside the package's
  control.
- Skip the incremental filter (re-select and merge every row) whenever
  `waterfall__cohort_mode == 'current_state'`, relying on the existing
  `unique_key` for dbt's merge/upsert to update stale rows in place
  rather than duplicate them. (Chosen.)
- Refuse `current_state` entirely at compile time unless
  `--full-refresh` is also passed. Rejected as more disruptive than
  necessary -- the "skip the filter" option gets full correctness without
  requiring the user to remember an extra flag every time.

## Decision Outcome

Chosen option: `waterfall__movement_detail`'s incremental filter is now
gated on `is_incremental() and waterfall__cohort_mode != 'current_state'`.
Under `cohort_at_open` (the default), behavior is unchanged. Under
`current_state`, every run re-selects every period's transitions and
relies on `unique_key = 'movement_detail_id'` (a surrogate of `entity_id`,
`source_relation`, `period_grain`, `period_start`) to merge-update each
period's existing row in place -- no duplication, and every period's
`bridge_amount` reflects the CURRENT run's "latest date," matching what
`bridge_reconciles`/`mart_bridge_reconciles` compute live in the same run.

### Consequences

- Good, because `dbt build --vars '{waterfall__cohort_mode:
  current_state}'` now reconciles correctly whether it's the first build
  ever, or a build on top of an existing `cohort_at_open`-populated
  database (the realistic case CI caught).
- Good, because `cohort_at_open`'s incremental behavior (the default,
  what nearly every user will actually run) is completely unchanged.
- Bad, because `current_state` now does strictly more work per run (a
  full re-scan and merge of `int_waterfall__transitions` for every period,
  every time) than the original append-only design intended -- an
  accepted cost, since `current_state`'s whole premise is "recompute what
  today's data says," which cannot be done incrementally by definition
  without also detecting when the "latest date" has moved, which dbt's
  incremental materialization has no primitive for.

## Assumption this relies on

`unique_key`-based incremental merge (dbt's `delete+insert` or `merge`
strategy, whichever the target adapter defaults to) correctly replaces an
existing row rather than appending a duplicate when the query re-selects
a `period_start` already present in the relation. Confirmed for DuckDB via
the reproduction below.

## Known limitation

This does not make `current_state` cheap at scale -- a large,
long-running project on `current_state` will re-scan and re-merge its
entire transition history every single run. That cost is inherent to the
mode's own definition (BUILD-PLAN.md §5: "will change as later syncs
land"), not an artifact of this fix, and isn't addressed here.

## Confirmation

Reproduced the exact CI sequence locally: `dbt deps` -> `dbt compile`
(cold) -> `dbt docs generate` (cold) -> remove the DB -> `dbt build`
(default) -> `dbt build --vars '{waterfall__cohort_mode:
current_state}'` (no `--full-refresh`, same DB). Before this fix:
`assert_empty_bridge_reconciles_` and `assert_empty_mart_bridge_reconciles_`
both fail with 2 non-zero-delta rows each. After this fix: the same exact
sequence passes, a second consecutive `current_state` run also passes,
and switching back to the default `cohort_at_open` on the same database
afterward still passes -- confirming no regression to the default,
far-more-common path.

---
status: accepted
date: 2026-08-30
decision-makers: Kate Kruger
---

# Guard every compile-time run_query() against cold warehouses and unit tests

## Context and Problem Statement

An external audit (ENG-7e, item 3, and ENG-7b, 30 Aug 2026) found two
distinct, previously-unreproduced failure modes in the four places this
package calls `run_query()` at compile time to resolve a literal date
(`int_waterfall__period_boundaries.sql`'s min/max bounds, and the
`waterfall__cohort_mode = 'current_state'` "latest known snapshot"
lookup duplicated in `int_waterfall__transitions.sql`,
`models/preflight/bridge_reconciles.sql`, and
`models/preflight/mart_bridge_reconciles.sql`):

1. `dbt compile` and `dbt docs generate` against a cold/empty warehouse
   both failed with a "table does not exist" error, despite an existing
   `{% if execute %}` guard. `execute` is `True` for both of those
   commands (they run introspective queries against the real target, not
   just static parsing) -- it does not mean "the relations I'm about to
   query have been built."
2. Running `dbt build --vars '{waterfall__cohort_mode: current_state}'`
   failed on `bridge_reconciles`'s own unit test
   (`test_bridge_reconciles_fires_on_vanished_entity`) with a
   `run_query`-related compile error. dbt's unit-test compiler rewrites
   every `ref()`/`source()` inside the model under test into an injected
   fixture CTE, but a `run_query()` call issued from inside `{% set %}`
   Jinja is a separate ad hoc query against the real adapter -- it is NOT
   rewritten the same way, and fails looking for a relation the unit test
   never actually builds.

Only (1) is a genuine risk to downstream consumers (a user running
`dbt docs generate` before ever running `dbt build`). (2) only affects
this repository's own CI, since a downstream project's `dbt build` does
not run an installed package's unit tests by default -- but it makes the
package's own `dbt build` (this repo's CI command) fail whenever anyone
develops against `current_state`, which is exactly the mechanism ENG-7b's
"documented config options break the build" finding actually reproduces
here, even though the audit's originally-suspected root cause
(incremental-strategy staleness across repeated runs) did not reproduce --
confirmed by running the real build twice under `current_state`, which
reconciles cleanly both times once (2) above is fixed.

## Decision Drivers

- AGENTS.md rule 9 / BUILD-PLAN.md §2: the package would rather fail
  loudly than hand back a wrong number -- but that posture only works if
  the *tooling* itself doesn't fail for reasons unrelated to data
  correctness. A `dbt compile` crash on a fresh clone is the opposite of
  a helpful, named-fix failure.
- The existing four `run_query()` call sites were written independently
  and deliberately (see `bridge_reconciles.sql`'s own comment on why its
  current_state logic is duplicated rather than shared via a macro) --
  any fix has to preserve that independence, not introduce a new shared
  macro that would recouple them.

## Considered Options

- A shared macro wrapping `run_query()` with both guards. Rejected: would
  recouple `bridge_reconciles.sql`'s intentionally-independent
  current_state logic back to `int_waterfall__transitions.sql`'s, which
  is the exact coupling ADR 0004 avoided on purpose.
- Guard with `adapter.get_relation(...)` / `load_relation(...)` (relation
  existence) for the cold-warehouse case, and a separate
  `model.resource_type != 'unit_test'` check for the unit-test case,
  duplicated at each of the four call sites. (Chosen.)
- Disable `current_state` unit-testing entirely by removing
  `waterfall__cohort_mode` from what unit tests can vary. Rejected as
  broader than needed -- the actual unit tests in this package don't
  depend on `current_state` semantics at all; they supply their own
  `period_boundaries`/`daily_state` fixtures directly regardless of what
  `waterfall__cohort_mode` an invocation happens to be running under.

## Decision Outcome

Chosen option: at each of the four `run_query()` call sites, gate the
call on `execute and model.resource_type != 'unit_test' and
load_relation(ref(...)) is not none`, falling back to the existing
`'1900-01-01'` sentinel otherwise. Duplicated at each site rather than
factored into a macro, consistent with the existing
independence-by-design in this part of the codebase.

`load_relation()` (not a raw `adapter.get_relation()` call) is used
because it returns `None` cleanly for a relation that doesn't exist yet
without erroring, which is exactly the cold-warehouse case being guarded
against.

`model.resource_type != 'unit_test'` was found by inspecting
`model.resource_type` inside the compiling context (it is literally
`'unit_test'` when dbt is compiling this model on behalf of one of its
own `unit_tests:` entries, vs. `'model'` for a normal build) -- this is
the narrowest available signal that distinguishes "being unit-tested"
from "being built or introspected for real," and does not depend on any
CLI-flag heuristic that could change between dbt versions.

### Consequences

- Good, because `dbt compile` and `dbt docs generate` now succeed on a
  cold/empty warehouse -- added to CI (see `.github/workflows/ci.yml`) so
  this can't regress silently again.
- Good, because `dbt build` under `waterfall__cohort_mode: current_state`
  now succeeds, twice in a row, including this package's own unit tests --
  added as an integration test.
- Bad, because the sentinel-fallback behavior for a unit test compiling a
  `current_state`-dependent branch means no unit test in this package can
  currently exercise `current_state`'s live-latest-date logic itself
  (only the parts of these models that don't depend on it). If a future
  PR needs to unit-test that behavior specifically, it will need a
  different mechanism (e.g. asserting against `int_waterfall__transitions`
  output from a real `dbt build` fixture run, not a `unit_tests:` block).

## Assumption this relies on

`model.resource_type` continues to report `'unit_test'` while compiling a
model on behalf of a `unit_tests:` entry, and `load_relation()` continues
to return `None` (rather than raising) for a relation that hasn't been
built. Both are documented, stable parts of the dbt Jinja context as of
dbt 1.12.

## Known limitation

This does not fix the general incompatibility between `run_query()` and
dbt's unit-test fixture-injection mechanism -- it works around it for the
four call sites that exist today by skipping the call entirely when
unit-tested. A future model that genuinely needs live introspection
*and* needs to be unit-testable would hit the same wall and need a
different design (e.g. computing the value as a plain SQL subquery
against the ref'd relation instead of a compile-time Python round-trip,
so dbt's ref-rewriting applies to it too).

## Confirmation

- `rm dev.duckdb && dbt compile` and `rm dev.duckdb && dbt docs generate`
  both fail before this fix (confirmed: `Catalog Error: Table ... does
  not exist`) and succeed after.
- `dbt build --vars '{waterfall__cohort_mode: current_state}'`, run twice
  in a row *starting from a freshly full-refreshed database*, fails
  before this fix (confirmed: a compile error in
  `test_bridge_reconciles_fires_on_vanished_entity`) and succeeds both
  times after, including `bridge_reconciles` and `mart_bridge_reconciles`
  passing on both runs.

## Correction (2026-08-30, same day)

The "Assumption this relies on" / Context section above states that the
originally-suspected incremental-staleness root cause "did not
reproduce." That conclusion was an artifact of this ADR's own test
methodology, not a correct finding: every local verification here started
from a database that had just been fully rebuilt (`rm dev.duckdb`)
immediately before switching to `current_state`, which incidentally forced
a full refresh and masked the actual bug. CI (PR #9, immediately after
this ADR's PR #8 merged) caught the real failure: running the *default*
`dbt build` first, then switching to `current_state` on that same
already-populated database -- the realistic sequence for an existing
project, and the one CI's own steps actually perform in order -- does
fail, with a genuine reconciliation delta, not a compile error. The
incremental-staleness theory was correct after all. See ADR 0010 for the
actual fix and root cause. This ADR's own fixes (the `run_query` guards
above) remain correct and necessary; they were simply not the whole
story.

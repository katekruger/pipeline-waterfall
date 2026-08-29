---
status: accepted
date: 2026-08-29
decision-makers: Kate Kruger
---

# Pipeline definition, bridge math, and preflight architecture

## Context and Problem Statement

Building `bridge_reconciles` ("opening pipeline + every movement bucket =
closing pipeline, exactly") surfaced that `waterfall__movement_detail`'s
`movement_amount` (built in Prompt 2) is a business-reporting figure, not a
bridge delta -- reusing it directly for reconciliation would be
mathematically wrong for several buckets. Proving the seven preflight
tests actually fire against broken input, without permanently breaking the
"20 good fixtures" build, also needed a real architecture, not just seven
independent SQL files. Several decisions fell out of working through the
arithmetic and the testing mechanics together.

## Decision Drivers

- "Exactly. Not within a tolerance." -- the bridge test has to be
  mathematically sound, not approximately right.
- "A preflight test you haven't seen fail is not tested" -- every one of
  the seven needs a genuine, observed failure, not just code that looks
  like it should fail.
- The standing `integration_tests/` build has to stay green -- it's the
  thing CI runs, and it's the credibility argument for the whole package.
- AGENTS.md: never hardcode a house opinion where BUILD-PLAN documents
  genuine disagreement; do write an ADR when a decision is expensive to
  reverse or not obvious from the code.

## Decision Outcome

### 1. `bridge_amount` is a new, separate column -- not a repurposed `movement_amount`

`movement_amount` answers "how big was the deal that did X" (business
reporting -- e.g. `won` under `terminal_wins` reports the full post-growth
amount). `bridge_amount` answers "how much did this row actually add to or
remove from open pipeline" -- computed generically, the same way for every
row regardless of bucket, as `pipeline_contribution_t1 -
pipeline_contribution_t0` (`int_waterfall__transitions.sql`), where
`pipeline_contribution = amount if (exists and not closed) else 0`, NULL
amounts coalesced to 0. These two numbers genuinely differ whenever a deal
both grows and closes in the same period (fixture 12: `movement_amount` =
13,000, `bridge_amount` = -10,000 -- only what was actually open at t0 ever
leaves pipeline) or is created and closed in the same period (fixture 4:
`movement_amount` = 12,000, `bridge_amount` = 0 -- it was never in opening
pipeline to begin with). `bridge_reconciles` sums `bridge_amount`, never
`movement_amount`.

### 2. `is_deleted` does not affect pipeline totals in v0.1

"Pipeline" (both opening and closing, and `pipeline_contribution`) is
defined purely as `is_closed = false`. A deal soft-deleted mid-period
(fixture 15) continues counting toward pipeline until it's actually closed.
This is a real, debatable choice -- arguably a deleted record shouldn't
count as real pipeline -- but there is no eleventh bucket to carry a
deletion's dollar removal (same tension as ADR 0002), and `waterfall__currency_mode`-style
scope creep into a new deletion-handling variable is out of scope for this
phase. Because pipeline is defined this way *consistently* everywhere (not
excluding deletes in some queries and not others), fixture 15 reconciles
correctly without any special-casing -- which is also, not incidentally,
what avoids the exact "naive implementation" bug the prompt for this phase
warns about: the bug isn't inherent to ignoring deletes, it's inherent to
excluding them *inconsistently*.

### 3. `hubspot_closedate_tracked` checks a var, not the (nonexistent) HubSpot adapter

The check reads `hubspot__deal_property_history_columns` directly,
independent of `waterfall__history_source` and the HubSpot adapter stub
(which raises a deliberate compiler error today -- v0.2). This is the only
way to prove the check fires at all in a Salesforce-only v0.1 build, and it
means the check activates the moment a user sets that var (e.g. while
preparing to migrate to HubSpot), which is arguably more useful than
gating it behind an adapter that doesn't exist yet.

### 4. Preflight checks are `models/preflight/*.sql` view models, not bare test files

Each computes violation rows (zero when healthy) with the BUILD-PLAN.md §6
message text as a column; a generic `assert_empty` test
(`macros/assert_empty.sql`) wired up per-model in `schema.yml` is what
actually fails the build. Building them as real, ref()-able models --
rather than files under `tests/` -- is what makes `unit_tests:` usable
against them: dbt's unit testing mocks a model's upstream `ref()`s with
synthetic rows, but only targets model nodes, not test nodes.

### 5. Proving each of the seven fires, split by what kind of "broken" it needs

- `stage_order_complete`, `history_gap`, `bridge_reconciles` need
  genuinely different *data* that can't coexist with the standing good
  seed -- proven with real `unit_tests:`, which mock the upstream ref and
  run as part of normal `dbt build`/CI. No seed pollution.
- `history_depth`, `hubspot_closedate_tracked`, `salesforce_history_enabled`,
  `multi_currency_unguarded` trigger purely off a `var`. Verified by hand
  with a separate `dbt build --select <name> --vars {...}` invocation
  (`dbt test` alone reuses the already-materialized view's baked-in Jinja
  values from the last build and won't reflect a new `--vars` override;
  `dbt build` re-renders the model first) -- commands and output in the
  Prompt 3 PR body, not automated in CI, the same pattern already used for
  Prompt 2's `movement_wins`/`period_end_open`/`current_state`.

### 6. Fixtures 17 and 19 removed from the standing seed; fixture 18 reclassifies; fixture 20 stays

Fixtures 17 (gappy history) and 19 (unknown stage) were built in Prompt 1
to prove the *contract* doesn't crash on them. Once `history_gap` and
`stage_order_complete` exist specifically to catch these exact patterns
and fail the build, leaving them in the standing seed would make the
package fail its own "good" build on every `dbt build`. They're removed
from `integration_tests/seeds/salesforce__opportunity_daily_history.csv`
and re-proven via the `unit_tests:` in decision 5, using the same data
shape they originally had. Fixture 20 (two currencies) stays --
`multi_currency_unguarded` only fires when `waterfall__currency_mode` is
*unset*, so `integration_tests/dbt_project.yml` now sets a placeholder
value for it, which keeps the fixture without weakening the check (unset
by default upstream; a real user still has to actively acknowledge it).

### 7. `int_waterfall__period_boundaries` had a real off-by-one, and one Prompt 2 fixture (`cohortmode-demo-1`) turned out incompatible with `bridge_reconciles`

Building `bridge_reconciles` against the standing seed surfaced a real bug
in Prompt 2's `int_waterfall__period_boundaries.sql`: its date spine
generated exactly `datediff(grain, min_date, max_date)` points, which
consistently left the *last real period* (the one containing `max_date`)
with no `lead()` value -- so `where period_end is not null` dropped the
last real period instead of the intended trailing partial one. Fixed by
extending the spine two periods past `max_date` instead of one, and by
additionally dropping any period whose `period_end` exceeds the data's
actual `max_date` (a period can have a non-null `period_end` and *still*
have no real closing data, if `max_date` lands exactly on a boundary).

Separately, Prompt 2's `cohortmode-demo-1` fixture (three rows, extending
into March, added purely to prove `cohort_at_open` and `current_state`
disagree) turned out incompatible with `bridge_reconciles` once it existed:
it was the *only* entity with a March row, so the February period's
"closing pipeline" only reflected that one entity while "opening pipeline"
reflected everyone still open at February -- a real (if artifactual)
reconciliation break. Removed from the standing seed rather than
backfilling every other open fixture with matching March data. Its
cohort-mode divergence remains verified and recorded in ADR 0003 -- that
verification is historically accurate for the fixtures as they existed in
Prompt 2 and isn't invalidated by the fixture's later removal, it's just no
longer independently reproducible from the current standing seed.

Also: `integration_tests/dbt_project.yml` overrides two package defaults
for this test harness specifically -- `waterfall__period_grain: ['month']`
and `waterfall__min_history_periods: 1` -- because this project's fixtures
are deliberately sparse (a handful of anchor dates, not continuous daily
rows) and span only one real month. Extending them to satisfy the
*package's* real defaults (quarter grain, 2 periods) was attempted and
reverted: it re-creates the exact "created" landmine fixture 4 exists to
catch (see decision 1) for every other fixture the moment a new period
boundary lands between the seed's start and where the real data begins.
Neither override changes the package's own `dbt_project.yml` defaults --
they're test-harness-only, and a real user's continuous history is exactly
what these checks need to test meaningfully.

Separately: fixture 18 (amount → NULL) reclassifies from unclassified to
`contracted`. `expanded`/`contracted` now coalesce amount to 0 for the
comparison (`macros/classify_movement.sql`) -- a NULL amount on a
previously-nonzero deal is a real, nonzero `bridge_amount` (the deal's
pipeline contribution genuinely dropped), and the old behavior (NULL
comparisons silently failing both predicates) left it invisible to the
bridge despite a real dollar impact. This is a correction to already-merged
Prompt 2 code, made here because building `bridge_reconciles` is what
exposed it.

### Consequences

- Good: the bridge is mathematically sound for every fixture, including
  the three cases (reopens, merges, deletes) the prompt specifically calls
  out as breaking naive implementations -- none of them needed special-
  case handling once `bridge_amount` was computed generically.
- Good: all seven preflight tests have an observed failure, not just
  plausible-looking code.
- Bad: four of the seven aren't exercised by CI directly, only documented
  manual verification -- consistent with existing precedent, but a real
  gap versus full automation.
- Bad: this PR modifies fixtures and a test file from an already-merged
  PR. Disclosed here and in the PR body rather than done quietly.

## Assumption this relies on

That `classify_movement` has no other gap where a row with a genuinely
nonzero `bridge_amount` falls through unclassified, beyond the two found
here (fixture 18, and the vanished-entity case proven in
`bridge_reconciles`'s own unit test). Because `bridge_amount` is computed
generically (not per-bucket), any *future* gap of this shape will still be
caught by `bridge_reconciles` against real data -- this assumption is about
what's already been found, not a claim that the classifier is now
exhaustively proven correct for every possible input.

## Known limitation

`is_deleted` is not excluded from pipeline totals (decision 2) -- a
deleted-but-still-open record continues appearing in `waterfall__bridge_*`
until it's actually closed, which some users will find surprising.
Four of seven preflight tests are var-triggered and only manually verified,
not covered by an automated CI assertion (decision 5).

## Confirmation

`models/preflight/schema.yml`'s three `unit_tests:` run as part of
`dbt build`/`dbt test` and fail if any of the three ever stop detecting
their scenario. The four var-triggered tests were run by hand with their
breaking `--vars` override during this PR; see the PR body for the actual
commands and output.

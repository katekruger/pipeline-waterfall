---
status: accepted
date: 2026-08-29
decision-makers: Kate Kruger
---

# Movement classification mechanics not fully pinned down by BUILD-PLAN.md §5

## Context and Problem Statement

BUILD-PLAN.md §5 names four contested definitions and the values each `var`
can take, but doesn't specify the SQL mechanics of how each alternative
actually differs from the default -- that's an implementation decision, not
just a lookup. Four separate calls were needed to build
`int_waterfall__transitions.sql`, `macros/classify_movement.sql`, and
`waterfall__movement_detail.sql`:

1. What does `waterfall__cohort_mode = 'current_state'` actually compute,
   concretely, as opposed to `'cohort_at_open'`?
2. What does `waterfall__slippage_definition = 'period_end_open'` actually
   compute, as opposed to `'close_date_period'`?
3. What does `waterfall__amount_change_precedence = 'movement_wins'`
   actually compute, as opposed to `'terminal_wins'`?
4. `waterfall__movement_detail`'s literal `unique_key` spec --
   `(entity_id, period_start, source_relation)` -- collides for real data.

## Decision Drivers

- Each of these is named and scoped by BUILD-PLAN.md §5 already -- the
  question isn't *whether* to build the alternative, it's *how*, and a
  wrong mechanical choice would make the toggle cosmetic rather than a real
  alternative.
- AGENTS.md: "every contested definition is a var with BOTH options
  documented and the consequence of each spelled out" -- an var whose
  alternate branch isn't exercised by anything isn't actually documented,
  it's decorative.
- BUILD-PLAN.md §5 calls `cohort_mode` "the single variable that most
  changes the reported number" -- this one specifically needed to produce a
  real, demonstrable divergence, not just parse without erroring.

## Decision Outcome

### 1. `cohort_mode`

`cohort_at_open` (default): every period's t1 snapshot is that period's own
`period_end` (the next period's `period_start` -- see
`int_waterfall__period_boundaries.sql`). Re-running a report on January
always returns the same numbers, because it's always comparing against
January's own period-end snapshot.

`current_state`: every period's t1 snapshot is `max(date_day)` across the
*entire* contract, not that period's own `period_end`. Reporting on January
after March's data has landed shows January's opening cohort against
*March's* state, not January's. Re-running the same report next month can
change the answer for a "closed" historical period. This is the
higher-blast-radius option BUILD-PLAN.md §5 describes, and it's implemented
that way deliberately -- see `integration_tests/seeds/salesforce__opportunity_daily_history.csv`'s
`cohortmode-demo-1` fixture (added specifically to prove the two modes
disagree; not one of the 20 canonical cases) and
`docs/decisions/0002-stage-regression-not-a-bucket.md`'s sibling reasoning
about what makes a definition worth its own fixture. Verified manually
(not in CI) with `dbt build --vars '{waterfall__cohort_mode: current_state}'`.

### 2. `slippage_definition`

`close_date_period` (default): three separate buckets, keyed on which
*period* a deal's `close_date` falls into -- `pushed` (in-period at t0,
moved to on/after this period's end), `pulled_in` (the mirror), `slipped`
(in-period at t0, still open at t1, close_date didn't leave the period).

`period_end_open`: BUILD-PLAN.md §5 cites Saber's glossary collapsing
pushed and slipped into one category as evidence there's no consensus.
Implemented as exactly that collapse -- any deal open at both boundaries
that wasn't pulled in is called `slipped`, whether or not its close_date
actually moved. `pulled_in` is untouched under both definitions: it isn't
contested the same way pushed-vs-slipped is, and BUILD-PLAN.md only names
an alternative for the pushed/slipped split.

### 3. `amount_change_precedence`

`terminal_wins` (default): the terminal bucket's `movement_amount` is the
full t1 amount -- the growth is absorbed, per BUILD-PLAN.md §5's own
example.

`movement_wins`: the terminal bucket's `movement_amount` is the t0 (pre-
movement) amount instead. **Scope decision:** this does NOT additionally
emit a second `expanded`/`contracted` row for the same entity-period to
carry the delta separately -- the row stays singular, only the dollar
figure attributed to the terminal bucket changes. A "the growth gets its
own row" implementation is a legitimate, arguably more complete reading of
"movement wins," but it means an entity can appear in `movement_detail`
twice for one period, which has knock-on effects on `waterfall__bridge_*`'s
grain and on `bridge_reconciles` (Prompt 3) that are out of scope to design
here. If that richer behavior is wanted later, it should be its own ADR,
not a silent change to this one.

### 4. `waterfall__movement_detail` unique_key

Added `period_grain` to the surrogate key documented in BUILD-PLAN.md §5:
`(entity_id, source_relation, period_grain, period_start)` instead of the
literal `(entity_id, period_start, source_relation)`. Four months a year
(Jan/Apr/Jul/Oct) start exactly on a quarter boundary, so a monthly and a
quarterly row for the same entity in one of those months would otherwise
collide on write. This is a correctness fix for a real bug in the literal
spec, not a preference -- see the model's own header comment.

### Consequences

- Good: all four toggles are real code paths with observed, different
  output, not documentation of an intention.
- Good: the `movement_detail` collision is fixed before it ever ships,
  rather than discovered by a user in a quarter-boundary month.
- Bad: `movement_wins`'s scope limitation (no second row) means it's a
  partial answer to "what if movement should win," not the most complete
  one imaginable. Documented above so nobody re-derives this from scratch.
- Bad: `current_state` mode is not covered by an automated CI test (doing
  so would require a second `dbt build` invocation with different vars);
  it was verified manually and that verification is recorded here instead.

## Assumption this relies on

That `int_waterfall__transitions` correctly excludes fixture 17's gappy-
history entity from every period (it has no row at any period boundary),
which is what makes `current_state` mode safe to implement as "join t1
against the single latest date_day globally" without also needing to
reconcile per-entity gaps in that same change. If a future entity-level
gap-filling behavior is added upstream, this mechanic should be revisited.

## Known limitation

`movement_wins` cannot currently express "attribute the terminal event and
the amount movement as two separate line items" -- see the scope note
above. `current_state` mode has no CI coverage, only the manually-recorded
verification in this ADR and the PR that introduced it.

## Confirmation

- `integration_tests/tests/assert_fixture_classification.sql` and
  `assert_precedence_cases_12_13.sql` confirm the default configuration.
- `cohortmode-demo-1`, `movement_wins`, and `period_end_open` were each
  verified by hand against a `dbt build`/`dbt run` invocation with the
  relevant var overridden -- see the PR this ADR shipped in for the exact
  commands and observed output.

## More Information

See `macros/classify_movement.sql` and
`models/intermediate/int_waterfall__transitions.sql` for the actual
implementation each of these decisions produced.

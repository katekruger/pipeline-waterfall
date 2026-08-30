---
status: accepted
date: 2026-08-30
decision-makers: Kate Kruger
---

# The bridge marts must expose bridge_amount, not just movement_amount

## Context and Problem Statement

An external audit (ENG-7a, 30 Aug 2026) found that `waterfall__bridge_monthly`
and `waterfall__bridge_quarterly` -- the models a RevOps user actually charts
-- only aggregated `movement_amount`. `bridge_amount`, the column ADR 0004
introduced specifically so `bridge_reconciles` could verify the headline
claim, was computed in `waterfall__movement_detail` but never surfaced in
either mart. A user building a waterfall chart from the model literally
named `bridge_monthly` got a number that reconciles to nothing, with no
documented way to discover that the real reconciling column lived one layer
upstream and wasn't in a model named after a bridge at all.

## Decision Drivers

- The package's first defensible claim (BUILD-PLAN.md §2) is "it
  reconciles" -- that claim is worthless if the model a user actually
  queries doesn't carry the column the claim is about.
- `movement_amount` is presumably meaningful for business reporting (it's
  what BUILD-PLAN.md §4 item 10's "3 large deals slipped" framing is about)
  and removing it would regress that.
- AGENTS.md: every model gets a description; ambiguity between two
  similarly-named dollar columns on the same row is exactly the kind of
  thing a description has to resolve, not leave to inference.

## Considered Options

- Rename `movement_amount` to `bridge_amount` in the marts and drop the
  business-reporting figure.
- Add `bridge_amount` alongside `movement_amount` in both marts, with the
  divergence documented explicitly.
- Leave the marts as-is and only document, in prose, that `bridge_amount`
  lives in `waterfall__movement_detail`.

## Decision Outcome

Chosen option: add `bridge_amount` alongside `movement_amount` in both
`waterfall__bridge_monthly` and `waterfall__bridge_quarterly`, because
dropping `movement_amount` would silently change the business-reporting
number for existing users with no correctness justification (unlike
`bridge_amount`, it was never wrong -- it was just misnamed relative to
what it's suited for), and requiring users to join back to
`waterfall__movement_detail` for the one column the package's headline
claim is about is the opposite of designing for the reader who charts the
mart directly.

A second preflight test, `mart_bridge_reconciles`, was added rather than
extending `bridge_reconciles` in place: it verifies the same invariant
against the mart's own `bridge_amount` column, independently of
`waterfall__movement_detail`, so a future regression that reintroduces this
exact gap (a mart column silently diverging from what actually
reconciles) fails the build again even if `bridge_reconciles` itself still
passes.

### Consequences

- Good, because a user querying `waterfall__bridge_monthly` /
  `waterfall__bridge_quarterly` directly can now build a reconciling
  waterfall chart without knowing `waterfall__movement_detail` exists.
- Good, because the ambiguity between the two dollar columns is now
  resolved in the schema.yml description of both columns, not left to
  inference.
- Bad, because the marts now carry two dollar columns per row, which is
  one more thing for a new user to be confused by before reading the
  descriptions -- mitigated by naming `bridge_amount`'s description "THE
  COLUMN TO CHART" explicitly, first thing, in the same style as the
  package's other loud-refusal conventions.

## Assumption this relies on

Every consumer of `waterfall__bridge_monthly` / `waterfall__bridge_quarterly`
reads the schema.yml column descriptions (or the model's dbt docs page)
before charting a column. This is the same assumption the package already
makes for every var and preflight test.

## Known limitation

This does not change `waterfall__movement_detail`, which already carried
`bridge_amount` correctly -- the bug was scoped entirely to the two
downstream marts not re-exposing a column that already existed one layer
up. It also does not add a third, blended column; a user who wants both
figures side by side still queries the same row for either.

## Confirmation

`mart_bridge_reconciles` (a new preflight test, `models/preflight/`) fails
the build if `sum(bridge_amount)` in either mart, for any period, does not
exactly equal that period's closing pipeline minus opening pipeline
(computed independently from `int_waterfall__daily_state`, mirroring
`bridge_reconciles`' own method). It was confirmed red (compile error: no
such column) against the pre-fix marts before the columns were added.

## More Information

See ADR 0004 for why `bridge_amount` exists as a separate column from
`movement_amount` in the first place.

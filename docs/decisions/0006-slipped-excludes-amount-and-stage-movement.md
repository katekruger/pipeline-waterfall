---
status: accepted
date: 2026-08-30
decision-makers: Kate Kruger
---

# `slipped` must not swallow deals that also advanced or moved dollars

## Context and Problem Statement

An external audit (ENG-7d, 30 Aug 2026) found that `advanced`, `expanded`,
and `contracted` were unreachable for any deal whose `close_date_t0` falls
within the reporting period -- which, for a current-quarter pipeline
review, is most of the open pipeline by definition. `slipped`'s condition
(`close_date_t0` in-period, still open at `t1`) checked nothing about
stage or amount, so it matched and won the CASE expression before
`advanced`/`expanded`/`contracted` were ever evaluated, regardless of
whether the deal had actually changed stage or size. A deal that grew from
10k to 25k while its close date sat unchanged in the current quarter was
reported as a 25k slip, not a 15k expansion.

This was a real, deliberate rule as documented (BUILD-PLAN.md §5), not a
typo -- the precedence table explicitly ranks date movement above amount
movement. But the *scope* of `slipped`'s condition (any in-period,
still-open deal, full stop) made that precedence rule bite far more often
than the precedence rule itself was meant to cover: it was written to
resolve genuine ties (a deal that is both slipping and growing), not to
suppress `advanced`/`expanded`/`contracted` for every deal that merely
happens to be due this quarter.

## Decision Drivers

- BUILD-PLAN.md §4 item 10: count *and* dollar variants of every bucket
  exist because "3 large deals slipped" and "40 small deals slipped"
  demand opposite responses -- a bucket that never fires for anything but
  slippage defeats that entirely.
- The precedence rule itself (terminal > reopened > date movement >
  advanced > amount movement) is load-bearing and BUILD-PLAN-documented;
  changing it wholesale would need its own audit of fixtures 12/13, which
  exist specifically to prove terminal and pushed outrank amount movement.
- AGENTS.md rule 2 (this task's ground rules): do not weaken
  `bridge_reconciles`. Any fix has to preserve exact reconciliation, not
  just plausible-looking bucket labels.

## Considered Options

- Reorder the CASE so amount movement outranks slippage globally. Rejected
  -- it just moves the bug: a deal that genuinely slipped (fixture 7: no
  stage or amount change) and also drifted by even $1 would then be
  reported as a trivial expansion/contraction instead of a slip, which is
  the worse failure mode for the exact scenario the audit calls out
  ("most of the pipeline" no longer showing as slipped at all).
- Narrow `slipped` to require that stage_order and amount are BOTH
  unchanged from `t0` to `t1`, falling through to `advanced` /
  `expanded` / `contracted` otherwise. (Chosen.)
- Emit `slipped` AND a separate movement row/column for whatever else
  changed, so nothing is lost. Rejected for v0.1 as the largest change --
  it alters `waterfall__movement_detail`'s grain (more than one bucket row
  per entity per period) and is a `waterfall__movement_detail`-shape
  change beyond this fix's scope; worth reconsidering for v0.2 if users
  ask for both facts simultaneously.

## Decision Outcome

Chosen option: narrow `slipped`'s condition (under both
`waterfall__slippage_definition` settings) to additionally require
`stage_order_t1 is not distinct from stage_order_t0` and
`coalesce(amount_t1, 0) = coalesce(amount_t0, 0)`. A deal is only
"slipped" now if literally nothing else about it changed except the clock
-- the moment it also advances a stage or moves dollars, it falls through
to `advanced`/`expanded`/`contracted` and is reported as that instead.

This keeps the documented precedence rule intact for the cases it was
actually meant to resolve: `pushed`/`pulled_in` (an explicit close-date
move to a different period) still outrank amount movement unconditionally
-- see fixture 13, still `pushed` after this change -- because a close
date literally moving to another period is a much narrower, stronger
signal than "this deal's close date happens to fall in the review period
and nothing about it changed."

`is not distinct from` (rather than `=`) is used for the stage_order
comparison so that two entities with the same untracked stage
(`stage_order` NULL at both `t0` and `t1`) are correctly treated as
"stage unchanged," matching how `amount` is separately coalesced to 0 for
its own comparison (ADR 0004) rather than letting a NULL propagate and
silently exclude the row from `slipped` for the wrong reason.

### Consequences

- Good, because `advanced`, `expanded`, and `contracted` are now reachable
  for any deal, including ones due to close in the current review period
  -- the common case this bug made effectively silent.
- Good, because `slipped` still fires for the actual "nothing happened,
  deadline passed" case (fixture 7) unchanged.
- Good, because `pushed`/`pulled_in`'s precedence over amount movement is
  untouched -- only `slipped`'s own condition narrowed.
- Bad, because a deal that is simultaneously "due this period" and
  growing is now reported purely as `expanded`, with no separate signal
  that its close date also didn't move -- a reader who wants both facts
  (it's due AND it grew) has to look elsewhere (e.g. `close_date` itself
  on the underlying contract). See the rejected "emit both" option above.

## Assumption this relies on

A RevOps reader would rather see a deal's most informative single
movement (it grew) than its least informative one (it's still open and
due sometime this quarter, which is true of most of the pipeline by
construction). If that assumption is wrong for a given org -- e.g. a team
that specifically wants "everything due this quarter and still open" as
its own cut regardless of other movement -- they can get it by querying
`int_waterfall__daily_state`/`int_waterfall__transitions` directly rather
than through `movement_bucket`.

## Known limitation

A deal that both advanced a stage AND moved dollars in the same period,
while its close date sat in-period and unmoved, is still resolved by the
existing `advanced` > `expanded`/`contracted` ordering below `slipped` in
the CASE -- this ADR does not touch that. It also does not change
`waterfall__amount_change_precedence` or the `terminal_wins` /
`movement_wins` split (ADR 0003) for deals that also close in the same
period.

## Confirmation

Two new fixtures (`integration_tests/seeds/salesforce__opportunity_daily_history.csv`):
`case21-grew-in-period-close-1` (amount 10000 -> 25000, close_date
unchanged at 2026-01-20, stays open) and
`case22-advanced-in-period-close-1` (stage Qualification -> Value
Proposition, amount and close_date unchanged, stays open). Both had an
in-period, unmoved `close_date` and were confirmed red -- misclassified as
`slipped` by `integration_tests/tests/assert_fixture_classification.sql`
-- before this fix, and now classify as `expanded` and `advanced`
respectively. `case07-slipped-1` (nothing else changed) and
`case13-pushed-and-expanded-1` (`pushed` still outranks amount movement)
continue to pass unchanged, confirming the narrowing didn't regress the
precedence rule itself.

---
status: accepted
date: 2026-08-29
decision-makers: Kate Kruger
---

# Stage regression is not a movement bucket in v0.1

## Context and Problem Statement

A deal's `stage_order` can decrease between two observations (fixture 14 in
`integration_tests/seeds/`) -- a rep moves a deal back to an earlier stage.
Every waterfall implementation surveyed either ignores this or handles it
inconsistently (see BUILD-PLAN.md §5's edge-case table, row 5: "Undefined in
every implementation I found"). Should a stage-order decrease be its own
movement bucket, folded into an existing one, or left unclassified?

## Decision Drivers

- BUILD-PLAN.md §5 locks the v0.1 bucket list to exactly ten: `created,
  won, lost, reopened, pushed, pulled_in, slipped, advanced, expanded,
  contracted`. Adding an eleventh bucket here would be redefining that
  contract from inside a fixture-design decision, not proposing it.
- `advanced` is explicitly defined as "`stage_order` increased" -- folding a
  decrease into it as a negative value would make the bucket mean "stage
  changed" instead of "stage moved forward," which corrupts every reading of
  `advanced` as a forward-momentum signal.
- `bridge_reconciles` (Prompt 3) requires opening pipeline + every movement
  bucket = closing pipeline, exactly. A bucket only needs to exist if it
  explains a change in the deal's contribution to bridge dollars.

## Considered Options

- Fold into `advanced` as a negative count/amount
- Add an eleventh bucket, `regressed`
- Leave a pure stage-order decrease unclassified (no bucket) in v0.1

## Decision Outcome

Chosen option: "Leave a pure stage-order decrease unclassified in v0.1."

A stage-order decrease with no other qualifying change (amount unchanged,
close date unchanged, still open) does not change the deal's contribution to
bridge dollars -- it's still open, at the same amount, in the same period.
It therefore does not need a bucket for `bridge_reconciles` to hold, and
`advanced` stays strictly "moved forward" with no sign ambiguity.

If a stage change is *also* an amount or date change, it's already covered:
the amount/date bucket applies regardless of which direction the stage
moved. Fixture 14 covers the pure case -- stage moves back, nothing else
changes -- specifically so this is testable in isolation.

### Consequences

- Good: `advanced` keeps a single, unambiguous meaning (forward stage
  progress) with no sign convention to document or get wrong.
- Good: no change needed to BUILD-PLAN.md's locked ten-bucket contract.
- Bad: a rep who repeatedly bounces a deal backward and forward produces no
  visible signal in `movement_detail` today. That's a real gap for anyone
  who wants stage-momentum/deal-health visibility, not just a bridge.

## Assumption this relies on

That bridge reconciliation (dollars in = dollars out) is the v0.1 product,
not deal-health scoring. If a future version's positioning shifts toward
per-deal health signals rather than pipeline-dollar reconciliation, this
assumption should be revisited.

## Known limitation

Stage regressions are invisible in `waterfall__movement_detail` in v0.1.
Anyone who wants to know "how many deals moved backward this period" cannot
get that from this package yet. Flagged as a v0.2+ idea below, not
committed to any version.

## Confirmation

`int_waterfall__daily_state` fixture 14 (`case14-stage-regression-1` in
`integration_tests/seeds/salesforce__opportunity_daily_history.csv`) carries
a stage decrease with amount and close_date held constant. When Prompt 2's
classifier is built, a test should assert this fixture lands in **no**
bucket -- confirming the decision is implemented, not just documented.

## Pros and Cons of the Options

### Fold into `advanced` as negative

- Good, because no new bucket to build or explain
- Bad, because it silently redefines what a positive `advanced` count means
  wherever a user has read the bucket as "forward momentum only"
- Bad, because count and dollar variants (BUILD-PLAN.md §5, feature #10)
  would need a sign convention nothing else in the package uses

### Add an eleventh bucket, `regressed`

- Good, because it gives real visibility into a real behavior
- Neutral, because it's a legitimate v0.2+ feature, just not one that can be
  added unilaterally inside Prompt 1's fixture work without amending
  BUILD-PLAN.md's locked bucket list first
- Bad, because it touches `waterfall__movement_detail`'s schema and the
  reconciliation math, which is Prompt 2/3 scope, not Prompt 1

### Leave unclassified (chosen)

- Good, because it requires no change to the locked contract
- Good, because it's provably correct for reconciliation: an unclassified
  transition that doesn't change amount/date/status can't unbalance the
  bridge
- Bad, because the stage-momentum signal is simply absent, not deferred with
  a visible placeholder

## More Information

If stage-momentum visibility becomes a real ask, revisit as a new ADR
proposing an eleventh bucket, rather than reopening this one -- see
`docs/decisions/0001-record-architecture-decisions.md` on superseding vs.
amending.

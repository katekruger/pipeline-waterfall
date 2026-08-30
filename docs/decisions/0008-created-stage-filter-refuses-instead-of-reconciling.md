---
status: accepted
date: 2026-08-30
decision-makers: Kate Kruger
---

# `created_stage_filter` gets a named refusal, not a full fix, in v0.1

## Context and Problem Statement

An external audit (ENG-7c, 30 Aug 2026) found that setting
`waterfall__created_stage_filter` to anything other than the default `[]`
breaks `bridge_reconciles`. The var is documented in the README's
configuration table with no warning. Reproduced directly: with
`waterfall__created_stage_filter: ['Prospecting']`, an entity created in
`Qualification` this period no longer classifies as `created` (correct,
per the filter), but is still open and counted in closing pipeline (via
`int_waterfall__daily_state`, which has no concept of this filter at
all) -- so the bridge's opening + movements no longer equals closing, by
exactly that entity's amount, and the build fails.

## Decision Drivers

- AGENTS.md rule 9 / BUILD-PLAN.md §2: fail loudly with a named fix,
  don't hand back a wrong number quietly. A documented config option that
  breaks the build with no indication of *why* is the worst version of
  this -- worse than not offering the option at all.
- Making `created_stage_filter` fully consistent (excluding filtered
  entities from pipeline totals, not just the `created` bucket) is a
  materially larger change than this fix's scope: it requires deciding,
  and modeling, when such an entity should *start* counting toward
  pipeline (the first period it reaches a filter-matching stage?
  never, until some other event?) -- a genuine v0.2-scale design question,
  not a one-line correction.
- Ground rule for this remediation pass: do not weaken `bridge_reconciles`
  to make this pass. `bridge_reconciles` firing here is *correct* --
  the fix has to explain the failure, not suppress it.

## Considered Options

- Exclude filtered-created entities from closing pipeline consistently,
  by carrying "does this entity's creation stage pass
  `created_stage_filter`" through `int_waterfall__daily_state` (or a new
  intermediate layer) and using it to gate pipeline_contribution
  everywhere. Rejected for v0.1 -- this changes the shape and meaning of
  "pipeline" itself (BUILD-PLAN.md's contract), needs its own design pass
  on what happens when such an entity later reaches a qualifying stage,
  and risks silently changing `history_depth`/`multi_currency_unguarded`
  and every other check built on `int_waterfall__daily_state`'s current,
  filter-unaware pipeline definition.
- Refuse the specific broken combination loudly, at compile time, naming
  the excluded entity/stage and the fix. (Chosen.)
- Leave the (accurate but unexplained) `bridge_reconciles` failure as the
  only signal, and add a README warning only. Rejected -- BUILD-PLAN.md
  §6's own preflight-test philosophy is that every failure names the
  fix; a generic reconciliation delta doesn't tell a user
  `created_stage_filter` is the cause without them already knowing to
  suspect it.

## Decision Outcome

Chosen option: a new preflight test, `created_stage_filter_excludes_pipeline`,
fires specifically when `waterfall__created_stage_filter` is set and would
exclude an entity that `classify_movement` would otherwise call `created`
this period -- computed independently off `int_waterfall__transitions`'
raw columns, not off `classify_movement`'s own filter logic, so a bug in
one couldn't hide it from the other (same independence principle as
`bridge_reconciles` itself, ADR 0004). Its message names the entity, the
excluded stage, the amount at stake, and the two available fixes (add the
stage to the filter, or unset the filter) plus this ADR. The README's
config table and preflight list are both updated with an explicit ⚠️
warning rather than a bare entry.

This is a *refusal*, not a fix: `created_stage_filter` remains genuinely
unsafe to use with any stage list that would exclude an otherwise-open
"created" entity. `bridge_reconciles` still fails in that scenario, now
alongside a check that explains why.

### Consequences

- Good, because a user who turns on `created_stage_filter` and hits a
  build failure now gets a message naming the exact cause and two
  concrete fixes, instead of a bare reconciliation delta.
- Good, because the check is computed independently of
  `classify_movement`'s own filter application, so it can't be defeated
  by the same bug it exists to catch.
- Bad, because `created_stage_filter` is still not usable for its
  apparent purpose (excluding early-funnel opportunities from the
  waterfall entirely) without also breaking reconciliation for any
  filtered entity that's still open at period end -- a user who wants that
  behavior has no working option in v0.1 beyond accepting the build
  failure or choosing a filter list broad enough to never exclude
  anything real.

## Assumption this relies on

A user who sets `created_stage_filter` reads the preflight failure
message (or the README warning) before assuming the var works as its name
implies.

## Known limitation

This does not make `created_stage_filter` usable for excluding
early-funnel opportunities from pipeline entirely -- that requires the
rejected option above (carrying filter-eligibility through the daily-state
contract) and is out of scope for v0.1. Consider for v0.2 alongside the
HubSpot adapter and multi-currency work, which also touch
`int_waterfall__daily_state`'s contract.

## Confirmation

`integration_tests`, with `waterfall__created_stage_filter: ['Prospecting']`
set: `case03-created-open-1` (created in `Qualification`, still open) no
longer classifies as `created`, remains in closing pipeline, and both
`created_stage_filter_excludes_pipeline` and `bridge_reconciles` fail --
confirmed before this fix (as a bare, unexplained `bridge_reconciles`
delta) and after (with the new test's named message alongside it). A new
unit test, `test_created_stage_filter_excludes_pipeline_fires`, proves the
new check fires on a minimal fixture without needing the full integration
build.

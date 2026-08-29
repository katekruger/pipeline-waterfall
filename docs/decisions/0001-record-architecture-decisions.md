---
status: accepted
date: 2026-08-29
decision-makers: Kate Kruger
---

# Record architecture decisions

## Context and Problem Statement

This package will accumulate genuinely contested decisions — pushed vs.
slipped, cohort-at-open vs. current-state, how to treat a stage regression,
whether a merge is detectable at all. Without a record, a future contributor
(human or agent) will "clean up" a deliberate choice without knowing it was
deliberate, or re-litigate a decision that was already settled with reasons
that no longer appear anywhere.

## Decision Drivers

- Decisions here are expensive to reverse once users depend on the behavior
- The reasoning behind a non-obvious choice is more valuable than the choice
  itself, and rots fastest when it isn't written down
- BUILD-PLAN.md documents the *what*; ADRs document the *why*, scoped to one
  decision each, permanently

## Considered Options

- No formal record — rely on commit messages and PR descriptions
- A single running `DECISIONLOG.md`
- Architecture Decision Records, one file per decision, MADR 4.0.0 format

## Decision Outcome

Chosen option: "Architecture Decision Records, one file per decision, MADR
4.0.0 format", because commit messages get lost from the file's blame history
across refactors, and a single running log doesn't scale to being linked from
individual models or referenced by number in a PR.

### Consequences

- Good, because a contested decision has one canonical, linkable location
- Good, because MADR's structure (drivers, options considered, consequences)
  forces the alternatives to be written down, not just the winner
- Bad, because it's one more file to write for decisions that turn out to be
  less contested than they first seemed

## Assumption this relies on

That decisions worth recording are rare enough that the overhead of writing
an ADR doesn't become a reason to avoid documenting them. If every PR seems
to need one, the bar in "when to write one" (see below) is being applied too
loosely.

## Known limitation

ADRs are backward-looking and permanent — they are not a substitute for
`docs/plans/`, which is forward-looking and disposable. Don't put a design
plan here, and don't put a permanent decision there.

## Confirmation

Reviewed at PR time: any PR that makes a decision non-obvious from the code,
or reverses a prior one, either includes a new ADR or updates an existing
one's status (`superseded by 000X`) rather than silently diverging from it.

## More Information

Format: [MADR 4.0.0](https://adr.github.io/madr/). Location:
`docs/decisions/NNNN-kebab-title.md`, four-digit, never renumbered, never
deleted. Two extra headings beyond the standard MADR template — "Assumption
this relies on" and "Known limitation" — borrowed from Fivetran's
`DECISIONLOG.md` discipline, because those two are what make a record useful
two years later.

Write one when a decision is expensive to reverse and non-obvious from the
code — especially for decisions *not* to do something.

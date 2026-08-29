# AGENTS.md

## Stop and read this before you write code

This repo has conventions. Violating them wastes a review cycle. This is a
dbt package (ships SQL models/macros via `packages.yml`, distributed through
dbt Hub) — not an application. There is no server, no UI, no API.

Read `BUILD-PLAN.md` before starting any phase of work; it is the source of
truth for architecture, the contract schema, movement-classification rules,
and the preflight test specs.

## Commands

- Install:   `cd integration_tests && uv run --with-requirements requirements.txt dbt deps`
- Build:     `cd integration_tests && uv run --with-requirements requirements.txt dbt build`
- Docs:      `cd integration_tests && uv run --with-requirements requirements.txt dbt docs generate`

There's no `pyproject.toml`/`uv.lock` declaring dbt as a dependency — `--with-requirements requirements.txt` is what actually resolves it. Plain `uv run dbt build` fails with "Failed to spawn: dbt".

`dbt build` runs against DuckDB using the fixtures seeded in
`integration_tests/seeds/`. No Salesforce, HubSpot, or dbt Cloud account is
needed for local development.

## Layout

- `macros/adapters/` — one macro per history source, normalizing to the
  contract (`int_waterfall__daily_state`). New source? New adapter macro, not
  a branch inside an existing one.
- `models/intermediate/` — the contract and everything derived from it before
  the public-facing outputs.
- `models/preflight/` — tests that fail the build, not warn.
- `seeds/` — example seeds users are expected to override (e.g. stage order).
- `docs/decisions/` — ADRs (MADR 4.0.0). Permanent, numbered, never renumbered.
- `docs/plans/` — dated design plans. Disposable once executed.
- `integration_tests/` — a complete nested dbt project. This is how the
  package proves itself without a real CRM connection.

## Non-negotiable

1. **Never commit directly to `main`.** Branch, commit, open a PR. Even for a typo.
2. **Tests before implementation.** If you are adding behavior, the failing
   fixture/test comes first.
3. **No secrets in the repo, ever** — not in tests, not in fixtures, not in
   examples.
4. **Never re-type a file's contents from tool output.** Output can be
   truncated. Edit in place.
5. **Every dependency added needs a one-line justification in the PR body.**
6. **If a decision is expensive to reverse, write an ADR in the same PR.**
7. **Every model gets a description in `schema.yml`. No exceptions.**
8. **Every contested definition is a `var` with BOTH options documented and
   the consequence of each spelled out.** Never hardcode a house opinion —
   see BUILD-PLAN.md §5 and §6 for the full list of what's contested.
9. **Preflight tests FAIL the build, they do not warn.** A silently wrong
   waterfall is worse than no waterfall.
10. **Never assume a Salesforce field is tracked.** Field history is capped
    at 20 fields per object and which ones are tracked is arbitrary per org.

## Before opening a PR

- [ ] `dbt build` passes locally in `integration_tests/`
- [ ] `CHANGELOG.md` has an entry under `## Unreleased` (once there's a
      user-facing change to note — not needed for pure scaffolding)
- [ ] No new model/macro lacks a fixture, or the PR says why
- [ ] The PR body discloses: model, harness, and that it was AI-assisted
- [ ] You showed the human the full diff and got approval

## What gets rejected

- Direct commits to `main`
- Reformatting unrelated code
- New dependencies without justification
- A hardcoded definition where BUILD-PLAN.md documents genuine disagreement
- Removing or weakening `bridge_reconciles` (or any preflight test) to make
  CI pass
- Anything that makes an approval gate optional

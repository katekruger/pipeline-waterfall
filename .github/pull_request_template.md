## What and why

<!-- What changed, and why. Link the issue/ADR if there is one. -->

## Checklist

- [ ] `dbt build` passes locally in `integration_tests/`
- [ ] Every new/changed model or macro has a description in `schema.yml`
- [ ] Every new contested definition is a `var` with both options documented
      (not a hardcoded house opinion)
- [ ] New behavior has a fixture proving it; new preflight tests have a
      deliberately-broken fixture proving they fire
- [ ] `CHANGELOG.md` updated under `## Unreleased` (if user-facing)
- [ ] A new ADR is included if this reverses or makes a hard-to-reverse
      decision (`docs/decisions/`)

## AI-assisted?

<!--
If any part of this PR was written with AI assistance, disclose it here:
which model, and which harness (Claude Code, Cursor, Copilot, etc.). This
isn't a gate on review — it's just honesty about provenance.
-->

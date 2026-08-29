# Going-public checklist

`pipeline-waterfall` is currently **private**. This is what to do at flip
time (Prompt 5), written now while the reasoning is fresh rather than
reconstructed later.

## Why private for now

Actions minutes are metered on private repos (~2,000/month on the free
tier). CI is deliberately kept to a single job while private — no version
matrix — to avoid burning through that budget on a repo nobody outside the
owner can see yet. Secret scanning, push protection, and CodeQL are also
free-and-automatic on public repos but generally require GitHub Advanced
Security on private ones.

## At flip time

- [ ] `gh repo edit katekruger/pipeline-waterfall --visibility public --accept-visibility-change-consequences`
- [ ] Enable secret scanning + push protection (now free and automatic)
- [ ] Enable CodeQL default setup (free on public repos)
- [ ] Enable private vulnerability reporting (referenced from `SECURITY.md`
      since Prompt 0 — confirm it's actually turned on)
- [ ] Expand `.github/workflows/ci.yml` to a real dbt-version matrix — Actions
      minutes are free on public repos, no reason to stay single-job
- [ ] Generate and upload a 1280×640 social preview image
- [ ] Submit to dbt Hub: PR to `dbt-labs/hubcap` editing `hub.json`, adding
      `"katekruger": ["pipeline-waterfall"]` — the hubcap bot can't see a
      private repo, so this can only happen after the flip
- [ ] Record a terminal GIF (`vhs`) showing `dbt build` against a
      deliberately-broken fixture with the `hubspot_closedate_tracked`
      preflight test failing, message and all. The refusal is the product —
      show the refusal, not a passing build. Goes directly under the README
      one-liner, above the badges.
- [ ] Cross-link from other repos (`awesome-gtm-engineering`, etc.)

See Prompt 5 in the prompts doc for the full sequence.

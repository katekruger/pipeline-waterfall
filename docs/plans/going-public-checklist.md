# Going-public checklist

`pipeline-waterfall` is **public** as of 2026-08-29. Status below reflects
what actually happened at flip time, not the original plan.

## Why it was private up to that point

Actions minutes are metered on private repos (~2,000/month on the free
tier). CI was deliberately kept to a single job while private — no version
matrix — to avoid burning through that budget on a repo nobody outside the
owner could see yet. Secret scanning, push protection, and CodeQL are also
free-and-automatic on public repos but generally require GitHub Advanced
Security on private ones.

## Done at flip time

- [x] `gh repo edit katekruger/pipeline-waterfall --visibility public --accept-visibility-change-consequences`
- [x] Secret scanning + push protection enabled
- [x] CodeQL default setup enabled
- [x] Private vulnerability reporting enabled (already referenced from
      `SECURITY.md` since Prompt 0)
- [x] `.github/workflows/ci.yml` expanded to a real dbt-version matrix
      (1.10.9 and 1.12.3 — the ends of the declared `require-dbt-version`
      range), verified locally on both before trusting it in CI. Caught a
      real dbt-core 1.10.x / Python-version incompatibility in the
      process, unrelated to this package, fixed by pinning `--python 3.12`
      explicitly per matrix leg.
- [x] Terminal GIF recorded with `vhs` (`docs/assets/hubspot-closedate-preflight.gif`,
      `.tape` source alongside it) showing `dbt build` failing
      `hubspot_closedate_tracked` against a HubSpot config missing
      `closedate`, plus the actual message text (dbt's console output on
      failure is just a row count — needed a follow-up query to actually
      show it). Embedded under the README one-liner, above the badges.
- [x] Social preview image generated at exact 1280×640
      (`docs/assets/social-preview.png`, `.html` source alongside it) —
      **not yet uploaded**. GitHub doesn't expose social-preview upload via
      the REST API, only the web UI (Settings → General → Social preview).
      Manual step: upload `docs/assets/social-preview.png` there.

## Deliberately not done

- [ ] **dbt Hub submission.** Fork, branch, and `hub.json` edit are ready
      at `katekruger/hubcap` (branch `add-pipeline-waterfall`), but the PR
      to `dbt-labs/hubcap` was not opened. Their own
      [`package-best-practices.md`](https://github.com/dbt-labs/hubcap/blob/main/package-best-practices.md)
      asks submitters to have used the package in production for an
      extended period and to have git history showing organic iteration,
      not a same-day build — neither is true of this repo yet. Revisit
      once it's actually been run against real data, not just fixtures.
- [ ] Cross-link from other repos. No repo of the owner's is actually named
      `awesome-gtm-engineering`; nothing was touched.

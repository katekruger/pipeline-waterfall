# pipeline-waterfall — Build Plan

**A dbt package that computes B2B bookings and pipeline waterfall analytics from CRM opportunity history.**

Owner: Kate Kruger (`github.com/katekruger`)
Status: not started
Plan version: 1.0 — 28 Aug 2026
Research current as of: 28 Aug 2026

---

## 0. Handover context — read this first

If you are a fresh session picking this up, here is everything you need to know that is not obvious:

- **This is a dbt package, not an application.** It ships SQL models and macros, installs via `packages.yml`, and is distributed through dbt Hub. There is no server, no UI, no API.
- **The single most important research finding:** Fivetran shipped daily point-in-time opportunity/deal history models between Jan and Aug 2026 (`salesforce__opportunity_daily_history`, `hubspot__daily_deal_history`). **The history layer is solved. Do not rebuild it.** The differentiated work is the *movement classification layer* on top.
- **The second most important finding:** no dbt package anywhere computes a pipeline waterfall. I scanned the complete live `hub.json` (all 108 orgs) plus four independent web searches. dbt Labs themselves started this problem (`fishtown-analytics/salesforce`) and **abandoned it** — that repo is archived, Stitch-specific, Redshift-specific, and pre-dbt-1.0, and even it only produced a daily state spine, never a waterfall.
- **The hardest problem is not SQL. It is definitions.** "Slipped" vs "pushed" has no industry consensus. Getting the *configurability* right matters more than getting the math right, because every user will arrive with a house definition they consider correct.
- **A truly out-of-the-box package is not achievable** and the plan should not pretend otherwise. Every available history source is either disabled by default, not backfilled, capped at 20 tracked fields, or missing the close-date field. Loud preflight tests are a headline feature, not a chore.

---

## 1. The gap

### What exists

| Layer | Status |
|---|---|
| CRM staging models | **Solved.** `fivetran/dbt_salesforce` v2.4.1 and `fivetran/dbt_hubspot` v1.9.2, both last committed 2026-08-18, both Fusion-compatible. |
| Daily opportunity/deal history | **Solved as of 2026.** `salesforce__opportunity_daily_history` and `hubspot__daily_deal_history` (new in v1.9.0). Both grain: one row per entity per day. |
| Current-state pipeline rollup | Partially solved. `salesforce__sales_snapshot` exists but is a single-row current-state rollup with no period-over-period movement. |
| **Waterfall / movement classification** | **Does not exist. Anywhere.** |
| Source-agnostic CRM contract | **Does not exist.** The only serious attempt, `rittmananalytics/ra_data_warehouse`, is dead — last commit 2022-02-14, not on the Hub, no successor. |

### What is dead or irrelevant

- `fivetran/dbt_salesforce_source` — **archived 2026-01-20**, folded into `dbt_salesforce`. Do not depend on it.
- `fivetran/dbt_hubspot_source` — likewise deprecated.
- `fishtown-analytics/salesforce` (dbt Labs) — archived 2024-12-04. Read it for the shape, do not reuse the code.
- `dlt-hub/dlt-dbt-salesforce` — last commit 2025-02-01, no history models.
- `datalakehouse/dlh-salesforce-analytics-dbt` — stale since 2023.
- `fivetran/dbt_salesforce_formula_utils` — actively maintained but replicates *formula fields*, explicitly not history-related. Irrelevant except as a package users may also install.

### Why the gap persists

Waterfall analysis is universally rebuilt from scratch inside companies because it sits exactly at the seam between three things nobody owns together: loader-specific history mechanics, CRM-specific object semantics, and contested finance definitions. Commercial products exist (Sightfull, Weflow, Equals, Kluster, Saber) and all are closed.

---

## 2. Positioning

**One line:** the movement layer that turns CRM history into a reconciling pipeline bridge, without telling you what "slipped" means.

**Three defensible claims, in priority order:**

1. **It reconciles.** Opening pipeline + every movement bucket = closing pipeline, exactly, or a test fails. Most internal implementations do not reconcile and nobody notices until a board meeting.
2. **Every contested definition is a variable, with the alternative shipped and documented.** Not a house opinion with an escape hatch — genuinely both, side by side.
3. **It refuses to produce a wrong answer quietly.** If close-date history is missing, if the history window is shorter than the comparison period, if multi-currency amounts are being summed across currencies — the package fails loudly with a message naming the fix.

**What it is NOT:** a forecasting model, a BI tool, a replacement for Fivetran's staging layer, or an opinion about what your stages should be.

---

## 3. Scope

### v0.1 — the reconciling core (target: 3 weeks)

| In | Out |
|---|---|
| Salesforce via `salesforce__opportunity_daily_history` | Any non-Fivetran loader |
| The eight movement buckets + `pulled_in` + `reopened` | Multi-currency conversion |
| Bridge reconciliation test | Fiscal periods (calendar only) |
| Preflight tests for history depth and required fields | HubSpot |
| Monthly and quarterly grain | Line-item / product-level waterfall |
| `dbt docs` with every definition written out | A website |

### v0.2 — second CRM + currency (target: +2 weeks)

- HubSpot via `hubspot__daily_deal_history`, including the `closedate` preflight hard-fail (see §6)
- Multi-currency: record currency, corporate currency at close, corporate currency as-of-snapshot — as three explicit modes
- Fiscal period support (Salesforce exposes `fiscal_quarter`, `fiscal_year`, `fiscal`)

### v0.3 — the standard play (target: +3 weeks)

- **The source-agnostic history contract as a separately documented interface**, so a user on any loader can conform their own model to it and get the whole waterfall for free. This is the piece with the longest half-life and it is currently an open position in the ecosystem.
- dbt snapshot backend for users with no history mode
- Push-count tracking per deal (a third-push deal behaves differently from a first)

### Explicit non-goals, permanently

- Reimplementing DMARC-style history capture from raw `OpportunityFieldHistory` as the *primary* path — it is capped at 20 fields per object, arbitrary per org, and cannot be assumed. Support it as a fallback adapter only.
- Any write-back to the CRM.
- Opinionated stage taxonomy.

---

## 4. Feature inventory, scoped

Effort is calendar-days for one person who knows dbt. Verdict is the v0.1 call.

| # | Feature | Fills what gap | Effort | Verdict |
|---|---|---|---|---|
| 1 | History-source adapter layer (`var('waterfall__history_source')`) normalizing to one contract | The whole portability story | 4d | **v0.1** |
| 2 | Movement classification: `created`, `advanced`, `pushed`, `slipped`, `pulled_in`, `won`, `lost`, `expanded`, `contracted`, `reopened` | The core product | 5d | **v0.1** |
| 3 | Bridge reconciliation test (opening + movements = closing) | Nobody else does this | 2d | **v0.1** |
| 4 | Preflight: history depth ≥ 2 periods, required fields present, earliest `date_day` vs requested window | Prevents silent wrong answers | 2d | **v0.1** |
| 5 | Cohort mode var: `cohort_at_open` vs `current_state` | The definition that most changes the number | 2d | **v0.1** |
| 6 | Slipped/pushed definition vars | No industry consensus exists | 1d | **v0.1** |
| 7 | `waterfall__amount_column` var (Amount vs a custom ARR field) | ARR is always a custom field | 0.5d | **v0.1** |
| 8 | `waterfall__created_stage_filter` (all opps vs qualified-only) | Contested; default is wrong for mature orgs | 1d | **v0.1** |
| 9 | Terminal-event precedence for deals that both grew and closed | Prevents double-count | 1d | **v0.1** |
| 10 | Count *and* dollar variants of every bucket | "3 large" vs "40 small" demand opposite responses | 1d | **v0.1** |
| 11 | Monthly + quarterly grain | Table stakes | 1d | **v0.1** |
| 12 | `integration_tests/` with seeded fixtures covering every bucket | Credibility; also how you prove reconciliation | 3d | **v0.1** |
| 13 | HubSpot adapter | Second CRM | 4d | v0.2 |
| 14 | HubSpot `closedate` hard-fail preflight | Without it the waterfall has no slippage and looks fine | 1d | v0.2 |
| 15 | Multi-currency, three modes | Fivetran Salesforce has **zero** currency handling — real differentiator | 4d | v0.2 |
| 16 | Fiscal period support | B2B orgs report on fiscal | 2d | v0.2 |
| 17 | Merged-record handling (`master_record_id` / `stg_hubspot__merged_deal`) | A merge otherwise looks like a loss + an expansion | 2d | v0.2 |
| 18 | Soft-delete handling (`is_deleted` retroactively breaks the bridge) | Reconciliation correctness | 1d | v0.2 |
| 19 | Published history contract as a documented interface | The long-half-life artifact | 3d | v0.3 |
| 20 | dbt snapshot backend | Users with no history mode | 3d | v0.3 |
| 21 | Push-count per deal | Practitioner-requested nuance | 1d | v0.3 |
| 22 | `OpportunityFieldHistory` fallback adapter | Last resort for orgs without history mode | 4d | v0.3 |
| 23 | Owner / segment / region dimensional splits | Obvious next ask | 2d | v0.3 |
| 24 | Waterfall for line items / products | Deep, narrow | 5d | Deferred |
| 25 | A companion website with worked examples | Distribution | 3d | Deferred |

---

## 5. Architecture

### The one decision that matters

Everything hangs off a **normalized daily history contract**. Adapters read whatever the user has; the waterfall math reads only the contract. This is what makes the package CRM-agnostic and it is the piece worth publishing separately.

```
                  ┌─ adapter: fivetran_salesforce_history ─┐
raw history ──────┼─ adapter: fivetran_hubspot_history ────┼──▶ int_waterfall__daily_state
                  ├─ adapter: dbt_snapshot ────────────────┤         (THE CONTRACT)
                  └─ adapter: sf_field_history ────────────┘                │
                                                                            ▼
                                                            int_waterfall__period_boundaries
                                                                            │
                                                                            ▼
                                                            int_waterfall__transitions
                                                                            │
                                          ┌─────────────────────────────────┼──────────────────┐
                                          ▼                                 ▼                  ▼
                              waterfall__movement_detail      waterfall__bridge_monthly   ..._quarterly
                                  (one row per opp
                                   per period per bucket)
```

### The contract

`int_waterfall__daily_state` — grain: one row per `entity_id` per `date_day`.

| Column | Type | Notes |
|---|---|---|
| `entity_id` | string | opportunity/deal id |
| `date_day` | date | |
| `source_relation` | string | HubSpot models carry this; Salesforce models do **not**. Default `''` for SF. |
| `stage` | string | |
| `stage_order` | integer | resolved from a user-supplied stage seed; required for `advanced` |
| `amount` | numeric | column chosen by `waterfall__amount_column` |
| `currency_code` | string | nullable in v0.1 |
| `close_date` | date | |
| `is_closed` | boolean | |
| `is_won` | boolean | |
| `owner_id` | string | |
| `created_date` | date | |
| `is_deleted` | boolean | |

### Movement classification — the rules

Evaluated per entity, comparing state at period start (`t0`) to period end (`t1`). Terminal events win.

| Bucket | Rule |
|---|---|
| `created` | absent at `t0`, present and open at `t1`, `created_date` in period |
| `won` | `is_won` false→true |
| `lost` | `is_closed` false→true and `is_won` false |
| `reopened` | `is_closed` true→false |
| `pushed` | open at both, `close_date` moved to a **later period** |
| `pulled_in` | open at both, `close_date` moved to an **earlier period** |
| `slipped` | open at `t1`, `close_date` was in-period at `t0` and period ended with it unclosed |
| `advanced` | open at both, `stage_order` increased, close date unchanged |
| `expanded` | open at both, `amount` increased |
| `contracted` | open at both, `amount` decreased |

**Precedence:** terminal (`won`/`lost`) > `reopened` > date movement (`pushed`/`pulled_in`/`slipped`) > `advanced` > amount movement (`expanded`/`contracted`). A deal that grew and then closed-won lands in `won`, with the increment absorbed into the won amount. `waterfall__amount_change_precedence` exposes the alternative.

**`pushed` vs `slipped` are different measurements and are both required for the bridge to reconcile.** The default definitions above are configurable via `waterfall__slippage_definition`.

### Variable surface (v0.1)

```yaml
vars:
  waterfall__history_source: 'fivetran_salesforce_history'  # | fivetran_hubspot_history | dbt_snapshot
  waterfall__amount_column: 'amount'                        # e.g. 'arr_c'
  waterfall__stage_order_seed: 'waterfall_stage_order'      # user-supplied seed
  waterfall__cohort_mode: 'cohort_at_open'                  # | current_state
  waterfall__created_stage_filter: []                       # [] = all opportunities
  waterfall__slippage_definition: 'close_date_period'       # | period_end_open
  waterfall__amount_change_precedence: 'terminal_wins'      # | movement_wins
  waterfall__period_grain: ['month', 'quarter']
  waterfall__fiscal_periods: false
  waterfall__min_history_periods: 2                          # preflight hard-fail below this
```

### dbt project config

```yaml
name: 'pipeline_waterfall'          # ← this, NOT the repo name, is the Hub install name
version: '0.1.0'
require-dbt-version: [">=1.10.0", "<3.0.0"]   # MUST include 2.0.0 for Fusion
```

`require-dbt-version` including `2.0.0` is mandatory — packages excluding it warn now and error later, and the Hub renders a "Fusion compatible" badge plus an automated parse-test result. Set this correctly at v0.1.0; it is free marketing signal.

Materializations: `view` by default; `int_waterfall__daily_state` and `waterfall__movement_detail` as `incremental` with `unique_key` on a surrogate of (`entity_id`, `date_day`, `source_relation`).

---

## 6. Preflight tests — the differentiator, specified

These run as dbt tests and **fail the build**, not warn. Each has a message naming the exact fix.

| Test | Trigger | Message must say |
|---|---|---|
| `history_depth` | earliest `date_day` < 2 full periods before the requested window | "History begins YYYY-MM-DD. A waterfall for period X requires history from YYYY-MM-DD. Fivetran History Mode does not backfill." |
| `hubspot_closedate_tracked` | `'closedate'` not in `hubspot__deal_property_history_columns` | "HubSpot does not track close date in property history by default. Add `closedate` to `hubspot__deal_property_history_columns` and full-refresh. Without it, `pushed`, `pulled_in` and `slipped` will all be zero." |
| `salesforce_history_enabled` | `salesforce__opportunity_history_enabled` is false | "Set `salesforce__opportunity_history_enabled: true` in your dbt_project.yml." |
| `stage_order_complete` | any observed `stage` missing from the stage-order seed | lists the missing stages |
| `multi_currency_unguarded` | >1 distinct `currency_code` and `waterfall__currency_mode` unset | "Amounts in N currencies are being summed without conversion. Set `waterfall__currency_mode`." |
| `bridge_reconciles` | opening + movements ≠ closing, per period | reports the period and the delta |
| `history_gap` | any entity present on day N and day N+2 but absent on N+1 while open | "Gappy history detected. Fivetran dbt_salesforce <2.4.0 had a known bug here — upgrade." |

The HubSpot close-date one is the most important test in the package. Without it a user gets a waterfall that runs cleanly, reconciles, and reports zero slippage forever.

---

## 7. Known landmines (each of these will bite)

| Landmine | Detail | Mitigation |
|---|---|---|
| **History Mode does not backfill** | Fivetran: history is only guaranteed from the moment the table is switched to history mode. A new user has zero history on day one. | Preflight `history_depth`. Say it in the README's first section, not the FAQ. |
| **Re-syncs reset history** | Prior versions marked inactive; historical rows not preserved. | Document. Detectable via a sudden earliest-date jump. |
| **MAR cost** | Every source update becomes a destination row. High-velocity opportunity tables get expensive. | Document the cost tradeoff honestly in the README. Users will push back and should be warned first. |
| **Intra-sync changes are lost** | A deal that moved Stage 3→4→3 between syncs looks like it never moved. | Document as a known limitation of all daily-grain approaches. |
| **`on_schema_change='fail'` + `dbt_utils.star`** | Adding a tracked field breaks Fivetran's incremental until `--full-refresh`. | Note in troubleshooting. |
| **HubSpot stage is not in property history** | Verbatim comment in Fivetran's source. Stage is union'd in from `stg_hubspot__deal_stage` as a synthetic `field_name = 'pipeline_stage_id'`. | Adapter must handle this; do not assume symmetry with Salesforce. |
| **`source_relation` asymmetry** | HubSpot models carry it, Salesforce models don't. | Contract defaults it to `''`. Grain keys differ; handle in the adapter, not downstream. |
| **Salesforce multi-currency is unhandled by Fivetran** | Grepped every model and macro: no `currency_iso_code`, no conversion, nothing. Users on multi-currency orgs get amounts summed across currencies, silently wrong. | `multi_currency_unguarded` test. This is a genuine differentiator — nobody else catches it. |
| **Dated conversion rates** | Salesforce `DatedConversionRate` means the historically-correct rate varies by date. A point-in-time waterfall arguably needs the rate as of `date_day`. Nothing models this. | v0.2 decision. Document the chosen mode prominently. |
| **Amount is derived from line items** | Salesforce `amount` is the sum of line items whenever products are used — it moves without anyone editing the opportunity. | Document; affects `expanded`/`contracted` interpretation. |
| **Soft deletes break the bridge retroactively** | A deal deleted mid-period vanishes from history. | v0.2: carry `is_deleted` through the contract rather than filtering at staging. |
| **Fusion snapshot support is unverified** | The supported-features page lists snapshots neither way. | **Verify before committing to the v0.3 snapshot backend.** |

---

## 8. Repo structure

```
pipeline-waterfall/
├── dbt_project.yml              # name: 'pipeline_waterfall'
├── packages.yml                 # dbt_utils; NOT fivetran packages (users bring their own)
├── README.md
├── CHANGELOG.md
├── LICENSE                      # Apache-2.0 (match n8n-operator)
├── CONTRIBUTING.md
├── .github/
│   ├── workflows/ci.yml         # dbt build against integration_tests, on DuckDB
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── ISSUE_TEMPLATE/
├── macros/
│   ├── adapters/
│   │   ├── waterfall_source_fivetran_salesforce.sql
│   │   ├── waterfall_source_fivetran_hubspot.sql
│   │   └── waterfall_source_dbt_snapshot.sql
│   ├── classify_movement.sql
│   └── period_boundaries.sql
├── models/
│   ├── intermediate/
│   │   ├── int_waterfall__daily_state.sql        # THE CONTRACT
│   │   ├── int_waterfall__period_boundaries.sql
│   │   └── int_waterfall__transitions.sql
│   ├── waterfall__movement_detail.sql
│   ├── waterfall__bridge_monthly.sql
│   ├── waterfall__bridge_quarterly.sql
│   ├── schema.yml                                # every definition documented here
│   └── preflight/
│       └── *.sql                                 # singular tests
├── seeds/
│   └── waterfall_stage_order.csv                 # example; users override
├── docs/
│   ├── definitions.md            # the contested-definitions doc — a headline asset
│   ├── history-sources.md
│   └── contract.md               # v0.3: the publishable interface
└── integration_tests/
    ├── dbt_project.yml
    ├── packages.yml              # - local: ../
    ├── seeds/                    # fixtures exercising every bucket incl. edge cases
    └── tests/
```

---

## 9. Milestones

| # | Deliverable | Done when |
|---|---|---|
| M1 | Contract + Salesforce adapter | `int_waterfall__daily_state` builds from Fivetran history on seeded fixtures |
| M2 | Movement classification | All ten buckets classify correctly against fixtures covering every edge case |
| M3 | **Bridge reconciles** | `bridge_reconciles` test passes on fixtures including reopens, merges, and mid-period deletes |
| M4 | Preflight suite | All seven tests fire correctly on deliberately broken fixtures |
| M5 | Docs + `definitions.md` | Every var documented with both options and the consequence of each |
| M6 | CI green on DuckDB | `dbt build` in `integration_tests/` passes in Actions |
| M7 | **v0.1.0 released + Hub PR** | Tagged release, `hub.json` PR open at `dbt-labs/hubcap` |
| M8 | Fusion parse-test passes | Hub shows the "Fusion compatible" badge |
| M9 | HubSpot adapter + close-date preflight | v0.2 |
| M10 | Multi-currency, three modes | v0.2 |

---

## 10. Distribution

1. **dbt Hub.** PR to `github.com/dbt-labs/hubcap` editing `hub.json` — a flat org→repo map. `hubcap.py` runs hourly and auto-opens registry PRs on new GitHub releases. Requirements: GitHub-hosted, `dbt_project.yml` with a `name:`, semver releases, `packages.yml` at root.
2. **`dbt-labs/dbt-mcp`** (576 stars, the best-maintained thing in the category) is the natural distribution surface — a waterfall exposed through the dbt Semantic Layer MCP is a strong second-order story.
3. **dbt Slack** `#package-ecosystem` and `#tools-dbt-*` channels.
4. **`awesome-gtm-engineering`** — cross-link from the list you are also taking over.
5. **A written post: "Why your pipeline waterfall doesn't reconcile."** The reconciliation angle is the hook; the multi-currency finding (Fivetran has *zero* currency handling) is the surprising fact that makes it shareable.

---

## 11. Open questions to resolve before M1

1. **Does Fusion support dbt snapshots?** Blocks the v0.3 snapshot backend. Check the supported-features page and test with `dbtf build`.
2. **Confirm the Salesforce field-history limits** (20 fields per object, 18/24-month retention, untrackable field types). Current sources are secondary (Salesforce Ben, Gradient Works) and agree with each other, but `help.salesforce.com` is JS-rendered and could not be fetched. Do not put numbers in the README until confirmed from primary docs.
3. **HubSpot `deal_property_history` retention window and property cap** — Fivetran documents the stage exclusion and MAR impact but gives no retention limit. Unconfirmed.
4. **Decide the package `name:`** now, since the Hub install path derives from it and it is awkward to change later. Recommend `pipeline_waterfall`; install path becomes `katekruger/pipeline_waterfall`.
5. **Which warehouse for CI?** DuckDB is cheapest and Fivetran added DuckDB support 2026-08-18. Confirm the history models work there.

---

## 12. Sources

- [Building dbt packages](https://docs.getdbt.com/guides/building-packages) · [Packages](https://docs.getdbt.com/docs/build/packages) · [Fusion package upgrade guide](https://docs.getdbt.com/guides/fusion-package-compat) · [require-dbt-version](https://docs.getdbt.com/reference/project-configs/require-dbt-version)
- [dbt-labs/hubcap](https://github.com/dbt-labs/hubcap) · [hub.getdbt.com](https://hub.getdbt.com/)
- [fivetran/dbt_salesforce](https://github.com/fivetran/dbt_salesforce) · [fivetran/dbt_hubspot](https://github.com/fivetran/dbt_hubspot) · [fivetran/dbt_salesforce_source (archived)](https://github.com/fivetran/dbt_salesforce_source) · [fishtown-analytics/salesforce (archived)](https://github.com/fishtown-analytics/salesforce) · [rittmananalytics/ra_data_warehouse (dead)](https://github.com/rittmananalytics/ra_data_warehouse)
- [Fivetran History Mode](https://fivetran.com/docs/core-concepts/sync-modes/history-mode) · [Fivetran Salesforce connector](https://fivetran.com/docs/connectors/applications/salesforce) · [Fivetran HubSpot connector](https://fivetran.com/docs/connectors/applications/hubspot)
- [Salesforce Opportunity History vs Field History (Salesforce Ben)](https://www.salesforceben.com/salesforce-opportunity-history-vs-opportunity-field-history/) · [Field history tracking guide (Gradient Works)](https://www.gradient.works/blog/salesforce-field-history-tracking)
- [Pipeline Waterfall Analysis (Saber)](https://www.saber.app/glossary/pipeline-waterfall-analysis) · [How to Calculate Deal Slippage Rate (ORM)](https://orm-tech.com/blog/how-to-calculate-deal-slippage-rate) · [The Pipeline Metrics That Matter (David Sacks)](https://sacks.substack.com/p/the-pipeline-metrics-that-matter) · [Pipeline Movement Waterfall (Equals)](https://equals.com/use-cases/pipeline-movement-waterfall/)

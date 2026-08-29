# History sources

**A truly out-of-the-box CRM waterfall is not achievable, and this document exists to say exactly why.** Every available history source is either disabled by default, doesn't backfill, is capped on how much it tracks, or is missing a field the whole exercise depends on. That's not a shortcoming of this package — it's the actual state of every history mechanism available today. Pretending otherwise would make the first real waterfall someone runs silently wrong. Loud preflight tests exist because of everything below, not as a chore bolted on afterward.

## Salesforce, via `fivetran/dbt_salesforce`

**Source model:** `salesforce__opportunity_daily_history` (v2.4.1+). Grain: one row per opportunity per day.

- **Disabled by default.** Requires `salesforce__opportunity_history_enabled: true` in the consuming project's `dbt_project.yml`. Without it, the model this package's adapter reads from doesn't exist. Checked by `salesforce_history_enabled`.
- **History Mode does not backfill.** History is only guaranteed from the moment the connector is switched into history mode — a brand-new connection has zero usable history on day one, and a waterfall needs at least two full periods to say anything. Checked by `history_depth`.
- **Re-syncs can reset history.** A full historical re-sync marks prior versions inactive rather than guaranteeing they're preserved. Detectable, if it happens, as a sudden jump in the earliest observed `date_day`. Not currently a dedicated preflight check — watch for it if your `history_depth` result changes unexpectedly between runs.
- **Zero currency handling.** No `CurrencyIsoCode`, no conversion, nothing — even for orgs with Multiple Currencies enabled. `CurrencyIsoCode` only reaches this package's contract if a user has explicitly added `currency_iso_code` to `salesforce__opportunity_pass_through_columns`; even then, it's a passthrough field, not a converted one. Checked by `multi_currency_unguarded`. See `docs/definitions.md` for what "checked" does and doesn't mean here.
- **`amount` is derived from line items** whenever Products are used on the opportunity — it's the sum of the line items, not a field a rep edits directly. It moves without anyone touching the opportunity record, which affects how `expanded`/`contracted` should be read for orgs using Products.
- **Field history tracking is capped at 20 fields per object, and which 20 are tracked is arbitrary per org.** This package never assumes a given field is tracked — see `AGENTS.md`. It also means an `OpportunityFieldHistory`-based fallback adapter (not built in v0.1) can never be assumed complete; it's explicit non-goal territory for that reason (BUILD-PLAN.md §3).
- **`on_schema_change='fail'` plus `dbt_utils.star()`.** Adding a newly-tracked field to the upstream model breaks its incremental logic until a `--full-refresh`. Not this package's bug to fix, but worth knowing if a build starts failing right after a Salesforce admin adds field tracking.
- **Known history-gap bug, pre-2.4.0.** Versions of `fivetran/dbt_salesforce` before 2.4.0 could produce a daily-history table with an entity present on day N and day N+2 but silently absent on N+1, while still open. Checked by `history_gap` — the fix is to upgrade the package, not to work around the gap downstream.
- **Intra-sync changes are lost, structurally, at any daily grain.** A deal that moved Stage 3 → 4 → 3 between two syncs looks like it never moved at all. This is true of daily-grain history from any source, not specific to Fivetran — there's no preflight check for it because there's nothing to check; it's a resolution limit, not a bug.

## HubSpot, via `fivetran/dbt_hubspot` (not yet supported — v0.2)

**Source model:** `hubspot__daily_deal_history`. Not yet adapted by this package — selecting `waterfall__history_source: fivetran_hubspot_history` raises a clear compiler error rather than silently building nothing. Documented here because the landmines are already known and worth planning around before v0.2 ships.

- **HubSpot does not track close date in property history by default.** This is the single most important thing on this page. Without `closedate` added to `hubspot__deal_property_history_columns`, a waterfall built on HubSpot data runs cleanly, reconciles, and reports exactly zero slippage forever — `pushed`, `pulled_in`, and `slipped` are all silently zero. Nothing else would ever tell you this is happening; there's no error, no warning, just a suspiciously clean report. `hubspot_closedate_tracked` — checkable today even without the adapter, since it reads the Fivetran var directly — is built specifically to catch this before v0.2 ships, not after.
- **Stage is not tracked in property history either** — it's a verbatim limitation in Fivetran's own source. Stage is unioned in from `stg_hubspot__deal_stage` as a synthetic `field_name = 'pipeline_stage_id'`, not a real tracked property. The v0.2 adapter will have to handle this asymmetrically from Salesforce's `stage_name`, not assume the two sources look the same shape.
- **`source_relation` exists here but not on Salesforce.** HubSpot's Fivetran models carry a `source_relation` column for multi-connector union support; Salesforce's don't. The contract defaults it to `''` for Salesforce specifically so this asymmetry is handled once, in the adapter, rather than assumed away downstream (see `int_waterfall__daily_state`'s own documentation).
- **Retention window and property cap are undocumented.** Fivetran documents the stage exclusion and the MAR cost of tracking history, but not a hard retention limit or property cap for `deal_property_history`. Unconfirmed as of this writing — don't assume a number here.

## The `OpportunityFieldHistory` fallback (not built — last-resort only)

Reimplementing history capture from Salesforce's raw `OpportunityFieldHistory` table is an explicit, permanent non-goal as the *primary* path (BUILD-PLAN.md §3) — it's capped at 20 tracked fields per object, arbitrary per org, and can never be assumed complete. If it's ever built, it's a fallback adapter for orgs without History Mode access, not a replacement for the daily-history models above.

## General cost note

Every source update becomes a destination row under History Mode. A high-velocity opportunity table can get expensive to sync this way. This is a real tradeoff to have explicitly with whoever owns the Fivetran bill before turning history mode on — not a reason to avoid it, but not a free lunch either.

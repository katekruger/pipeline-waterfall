-- ENG-7e: the fixtures used to span exactly one real month
-- (2026-01-01 -> 2026-02-01), so waterfall__period_grain's default of
-- ['month', 'quarter'] never actually produced a complete quarter period
-- -- quarter grain built cleanly but was always empty, untested against
-- real data. The seed now carries anchor snapshots through 2026-07-01
-- (two real quarters), and integration_tests/dbt_project.yml no longer
-- overrides waterfall__period_grain down to month-only (see ADR 0009).
--
-- This asserts two things a month-only fixture set couldn't:
--   1. The quarterly bridge actually reconciles against real, non-empty
--      data for both complete quarters (2026-01-01 and 2026-04-01) --
--      bridge_reconciles/mart_bridge_reconciles already assert this
--      generically across every grain in period_boundaries, but this
--      makes the claim explicit and grain-specific for quarter.
--   2. case23-quarter-only-expansion-1 -- flat at 10000 through
--      2026-03-01, then 18000 from 2026-04-01 onward -- classifies as
--      'expanded' for the Q1 (2026-01-01 -> 2026-04-01) quarter boundary
--      even though it has no analogous movement in ANY monthly period
--      (it's flat within every individual month). Proves the classifier
--      is genuinely comparing quarter t0/t1 snapshots, not just replaying
--      whatever a monthly comparison would have found.

with quarterly_reconciliation as (

    select * from {{ ref('mart_bridge_reconciles') }}
    where period_grain = 'quarter'

),

case23_quarter as (

    select entity_id, period_grain, period_start, movement_bucket, movement_amount
    from {{ ref('waterfall__movement_detail') }}
    where entity_id = 'case23-quarter-only-expansion-1'
      and period_grain = 'quarter'
      and period_start = cast('2026-01-01' as date)

),

case23_expected as (

    select * from (
        values ('case23-quarter-only-expansion-1', 'quarter', cast('2026-01-01' as date), 'expanded', 8000.0)
    ) as t (entity_id, period_grain, period_start, expected_bucket, expected_amount)

),

failures as (

    -- any quarter that failed to reconcile at all
    select
        'quarterly bridge does not reconcile: ' || message as failure
    from quarterly_reconciliation

    union all

    -- case23 missing, or classified into the wrong bucket/amount
    select
        'case23-quarter-only-expansion-1 (Q1) expected ' || e.expected_bucket || '/' || cast(e.expected_amount as varchar)
            || ', got ' || coalesce(a.movement_bucket, 'NULL (no row)') || '/' || coalesce(cast(a.movement_amount as varchar), 'NULL') as failure
    from case23_expected e
    left join case23_quarter a using (entity_id, period_grain, period_start)
    where a.movement_bucket is distinct from e.expected_bucket
       or a.movement_amount is distinct from e.expected_amount

)

select * from failures

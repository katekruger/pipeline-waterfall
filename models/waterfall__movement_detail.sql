{{
    config(
        materialized = 'incremental',
        unique_key = 'movement_detail_id'
    )
}}

-- One row per opportunity per period per bucket. Every bucket carries both
-- a count (implicit: one row = one deal) and a dollar variant
-- (movement_amount), aggregated by waterfall__bridge_monthly/quarterly.
--
-- movement_amount is a business-reporting figure ("how big was the deal
-- that won/expanded/..."); bridge_amount is a different thing -- the
-- actual signed OPEN-PIPELINE delta this row is responsible for, computed
-- generically off int_waterfall__transitions regardless of bucket. The two
-- deliberately diverge (e.g. 'won' under terminal_wins reports the full
-- post-growth movement_amount but only ever removes what was actually open
-- at t0 from pipeline as bridge_amount) -- see ADR 0004 and
-- models/preflight/bridge_reconciles.sql, which sums bridge_amount, not
-- movement_amount.
--
-- Deviation from BUILD-PLAN.md §5's literal unique_key spec
-- ("a surrogate of (entity_id, period_start, source_relation)"): that key
-- omits period_grain. This model carries BOTH month and quarter grain rows
-- (see int_waterfall__period_boundaries), and four months a year start
-- exactly on a quarter boundary (Jan/Apr/Jul/Oct 1) -- so the literal key
-- collides for any entity with a movement in one of those months. Adding
-- period_grain to the surrogate is the minimal fix; see ADR 0003.

{% set amount_change_precedence = var('waterfall__amount_change_precedence', 'terminal_wins') %}

with transitions as (

    select *
    from {{ ref('int_waterfall__transitions') }}
    where movement_bucket is not null

),

with_amount as (

    select
        *,
        case
            -- terminal_wins (default): the full t1 amount, growth absorbed
            -- into the terminal bucket -- "a deal that grew and then
            -- closed-won lands in 'won', with the increment absorbed into
            -- the won amount" (BUILD-PLAN.md §5).
            --
            -- movement_wins: the terminal bucket only carries the deal's
            -- pre-movement (t0) amount, so a simultaneous expansion/
            -- contraction isn't credited to the terminal event. v0.1 does
            -- not additionally split this into a second expanded/contracted
            -- row for the same period -- see ADR 0003 for why, and for what
            -- a future version would need to change to do that.
            when movement_bucket in ('won', 'lost')
                then case
                    when '{{ amount_change_precedence }}' = 'movement_wins'
                        then coalesce(amount_t0, amount_t1)
                    else amount_t1
                end
            when movement_bucket in ('expanded', 'contracted')
                then coalesce(amount_t1, 0) - coalesce(amount_t0, 0)
            else amount_t1
        end as movement_amount,

        pipeline_contribution_t1 - pipeline_contribution_t0 as bridge_amount

    from transitions

)

select
    {{ dbt_utils.generate_surrogate_key(['entity_id', 'source_relation', 'period_grain', 'period_start']) }} as movement_detail_id,
    entity_id,
    source_relation,
    period_grain,
    period_start,
    period_end,
    movement_bucket,
    movement_amount,
    bridge_amount,
    stage_t1 as stage,
    currency_code_t1 as currency_code
from with_amount

{% if is_incremental() %}
where period_start > (select coalesce(max(period_start), cast('1900-01-01' as date)) from {{ this }})
{% endif %}

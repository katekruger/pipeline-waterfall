{{
    config(
        materialized = 'view'
    )
}}

-- One row per month per movement bucket: count and dollar variant both,
-- per BUILD-PLAN.md §5 ("3 large deals slipped" and "40 small deals
-- slipped" can be the same percentage and demand opposite responses).
-- Bridge reconciliation (opening + movements = closing, exactly) is
-- Prompt 3's job, not asserted here -- but note there are TWO dollar
-- columns and only one of them reconciles: bridge_amount is what to
-- chart for a waterfall (see mart_bridge_reconciles and schema.yml).

select
    period_start,
    period_end,
    movement_bucket,
    count(*) as movement_count,
    sum(movement_amount) as movement_amount,
    sum(bridge_amount) as bridge_amount
from {{ ref('waterfall__movement_detail') }}
where period_grain = 'month'
group by 1, 2, 3

{{
    config(
        materialized = 'view'
    )
}}

-- Same shape as waterfall__bridge_monthly, at quarterly grain.

select
    period_start,
    period_end,
    movement_bucket,
    count(*) as movement_count,
    sum(movement_amount) as movement_amount,
    sum(bridge_amount) as bridge_amount
from {{ ref('waterfall__movement_detail') }}
where period_grain = 'quarter'
group by 1, 2, 3

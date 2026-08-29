{{ config(materialized = 'view') }}

-- Fires when any observed stage in the contract has no match in the
-- stage-order seed (waterfall__stage_order_seed) -- a NULL stage_order.
-- Left silently, this stage can never trigger 'advanced' and its deals
-- quietly stop moving through the waterfall. Lists every missing stage,
-- not just the first, so one preflight run surfaces the whole gap.

with observed as (

    select distinct stage
    from {{ ref('int_waterfall__daily_state') }}
    where stage is not null
      and stage_order is null

)

select
    stage as missing_stage,
    'Stage "' || stage || '" is not in the stage-order seed (' || '{{ var("waterfall__stage_order_seed", "waterfall_stage_order") }}' || '). Add it, or deals in this stage will never be classified as advanced.' as message
from observed

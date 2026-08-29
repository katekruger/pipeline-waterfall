{{ config(materialized = 'view') }}

-- Fires when an entity is present on day N and day N+2 but absent on N+1,
-- while open on both sides -- the exact known bug fivetran/dbt_salesforce
-- had pre-2.4.0. Deliberately narrow (exactly a 2-day gap between
-- chronologically adjacent observations), not "any gap": a real, correctly
-- functioning daily-history table has one row per day, so any 2-day-apart
-- adjacent-observation pattern is anomalous. This package's own fixtures
-- intentionally use sparse, monthly-anchor rows rather than true
-- continuous daily data (see integration_tests/seeds/), which is a much
-- coarser gap than this check is tuned for -- narrowly targeting the known
-- bug pattern is what keeps this check meaningful without also flagging
-- this project's own fixture shape as broken.

with ordered as (

    select
        entity_id,
        source_relation,
        date_day,
        is_closed,
        lead(date_day) over (partition by entity_id, source_relation order by date_day) as next_date_day,
        lead(is_closed) over (partition by entity_id, source_relation order by date_day) as next_is_closed
    from {{ ref('int_waterfall__daily_state') }}

),

gaps as (

    select *
    from ordered
    where next_date_day is not null
      and {{ dbt.datediff('date_day', 'next_date_day', 'day') }} = 2
      and not coalesce(is_closed, false)
      and not coalesce(next_is_closed, false)

)

select
    entity_id,
    date_day as present_day_n,
    next_date_day as present_day_n_plus_2,
    'Gappy history detected for ' || entity_id || ' between ' || cast(date_day as varchar)
        || ' and ' || cast(next_date_day as varchar)
        || '. Fivetran dbt_salesforce <2.4.0 had a known bug here -- upgrade.' as message
from gaps

{{
    config(
        materialized = 'incremental',
        unique_key = 'daily_state_id'
    )
}}

-- THE CONTRACT. Grain: one row per entity_id per date_day. Every model
-- downstream of this one reads only from here -- see BUILD-PLAN.md §5.

with source as (

    {{ waterfall_get_daily_state_source() }}

),

surrogate_keyed as (

    select
        {{ dbt_utils.generate_surrogate_key(['entity_id', 'date_day', 'source_relation']) }} as daily_state_id,
        *
    from source

)

select *
from surrogate_keyed

{% if is_incremental() %}
where date_day > (select coalesce(max(date_day), cast('1900-01-01' as date)) from {{ this }})
{% endif %}

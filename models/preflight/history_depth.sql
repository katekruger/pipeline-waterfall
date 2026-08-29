{{ config(materialized = 'view') }}

-- Fires when the total observed date_day span in the contract is less
-- than waterfall__min_history_periods (default 2) full periods, for any
-- grain in waterfall__period_grain.
--
-- Deliberately a total-span check, not "does the earliest period have N
-- periods of history before it": int_waterfall__period_boundaries' own
-- date spine starts exactly at min(date_day) by construction, so the
-- first period NEVER has history before it, regardless of how much real
-- history exists -- that framing is unsatisfiable for any dataset, not
-- just short ones.

{% set grains = var('waterfall__period_grain', ['month', 'quarter']) %}
{% set min_periods = var('waterfall__min_history_periods', 2) %}

with bounds as (

    select
        cast(min(date_day) as date) as earliest_date,
        cast(max(date_day) as date) as latest_date
    from {{ ref('int_waterfall__daily_state') }}

),

{% for grain in grains %}
{{ grain }}_check as (

    select
        '{{ grain }}' as period_grain,
        earliest_date,
        latest_date,
        {{ dbt.datediff('earliest_date', 'latest_date', grain) }} as observed_periods
    from bounds

),

{% endfor %}

unioned as (

    {% for grain in grains %}
    select * from {{ grain }}_check
    {% if not loop.last %} union all {% endif %}
    {% endfor %}

)

select
    period_grain,
    earliest_date,
    latest_date,
    observed_periods,
    {{ min_periods }} as min_history_periods,
    'History begins ' || cast(earliest_date as varchar) || ' and only spans ' || cast(observed_periods as varchar)
        || ' full ' || period_grain || ' period(s). A waterfall needs at least ' || cast({{ min_periods }} as varchar)
        || '. Fivetran History Mode does not backfill, so a new connection has zero history on day one.'
        as message
from unioned
where observed_periods < {{ min_periods }}

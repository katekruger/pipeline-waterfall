{{
    config(
        materialized = 'view'
    )
}}

-- One row per period per grain in `waterfall__period_grain` (default
-- ['month', 'quarter']), spanning the actual date range present in the
-- contract. period_end is the NEXT period's start (an exclusive/telescoping
-- boundary: January's period_end == February's period_start), matching how
-- a period bridge normally works -- a period's closing state is the next
-- period's opening state. The last (partial, still-open) period per grain
-- is dropped since its period_end isn't known yet.

{% set bounds_query %}
    select
        cast(min(date_day) as date) as min_date,
        cast(max(date_day) as date) as max_date
    from {{ ref('int_waterfall__daily_state') }}
{% endset %}

{% if execute %}
    {% set bounds = run_query(bounds_query) %}
    {% set min_date = bounds.columns[0].values()[0] %}
    {% set max_date = bounds.columns[1].values()[0] %}
{% else %}
    {% set min_date = '1900-01-01' %}
    {% set max_date = '1900-01-01' %}
{% endif %}

{% set grains = var('waterfall__period_grain', ['month', 'quarter']) %}

with

{% for grain in grains %}
{% set spine_start = "date_trunc('" ~ grain ~ "', cast('" ~ min_date ~ "' as date))" %}
{% set spine_end = dbt.dateadd(grain, 1, "date_trunc('" ~ grain ~ "', cast('" ~ max_date ~ "' as date))") %}

{{ grain }}_spine as (
    {{ dbt_utils.date_spine(
        datepart=grain,
        start_date=spine_start,
        end_date=spine_end
    ) }}
),

{{ grain }}_periods as (

    select
        '{{ grain }}' as period_grain,
        cast(date_{{ grain }} as date) as period_start,
        cast(lead(date_{{ grain }}) over (order by date_{{ grain }}) as date) as period_end

    from {{ grain }}_spine

),

{% endfor %}

unioned as (

    {% for grain in grains %}
    select * from {{ grain }}_periods
    {% if not loop.last %} union all {% endif %}
    {% endfor %}

)

select *
from unioned
-- drop the trailing partial period per grain -- its period_end isn't in
-- the data yet, so there's nothing to compare against
where period_end is not null

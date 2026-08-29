{{ config(materialized = 'view') }}

-- Fivetran's Salesforce package has ZERO currency handling -- no
-- conversion, nothing. More than one currency_code in the contract means
-- amounts are being summed across currencies right now, silently, unless
-- the user has explicitly set waterfall__currency_mode acknowledging it
-- (real conversion is v0.2 -- BUILD-PLAN.md §3/§7). Nobody else catches
-- this.

{% set currency_mode = var('waterfall__currency_mode', none) %}

{% if currency_mode is none %}

with currencies as (

    select distinct currency_code
    from {{ ref('int_waterfall__daily_state') }}
    where currency_code is not null

),

counted as (
    select count(*) as currency_count from currencies
)

select
    currency_count,
    'Amounts in ' || cast(currency_count as {{ dbt.type_string() }}) || ' currencies are being summed without conversion. Set `waterfall__currency_mode`.' as message
from counted
where currency_count > 1

{% else %}

select cast(null as {{ dbt.type_int() }}) as currency_count, cast(null as {{ dbt.type_string() }}) as message where false

{% endif %}

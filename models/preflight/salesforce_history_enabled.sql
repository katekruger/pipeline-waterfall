{{ config(materialized = 'view') }}

-- fivetran/dbt_salesforce's salesforce__opportunity_daily_history model is
-- disabled by default (BUILD-PLAN.md §7) -- without this var set, the
-- model our Salesforce adapter reads from doesn't exist at all, so a new
-- user's build fails somewhere much less clear than here.

{% set enabled = var('salesforce__opportunity_history_enabled', false) %}

{% if not enabled %}

select
    cast('Set `salesforce__opportunity_history_enabled: true` in your dbt_project.yml.' as {{ dbt.type_string() }}) as message

{% else %}

select cast(null as {{ dbt.type_string() }}) as message where false

{% endif %}

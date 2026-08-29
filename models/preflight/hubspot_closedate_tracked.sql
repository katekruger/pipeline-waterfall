{{ config(materialized = 'view') }}

-- THE MOST IMPORTANT TEST IN THE PACKAGE. HubSpot does not track close
-- date in property history by default -- without it, pushed/pulled_in/
-- slipped are all silently zero forever, while the build still reconciles
-- cleanly (there's nothing for bridge_reconciles to disagree with; the
-- dollars just never move category). Nothing else would ever tell a user
-- this is happening.
--
-- Checked directly against the hubspot__deal_property_history_columns var
-- (a fivetran/dbt_hubspot project var), independent of
-- waterfall__history_source and the HubSpot adapter -- which isn't built
-- yet (v0.2; see macros/adapters/waterfall_get_daily_state_source.sql).
-- That decoupling is deliberate: it's what makes this checkable in
-- isolation at all right now, and it means the check activates the moment
-- a user sets this var (e.g. while preparing to switch to HubSpot), not
-- only once the adapter exists. See ADR 0004.

{% set hubspot_columns = var('hubspot__deal_property_history_columns', none) %}

{% if hubspot_columns is not none and 'closedate' not in hubspot_columns %}

select
    cast('{{ hubspot_columns | join(", ") }}' as {{ dbt.type_string() }}) as configured_columns,
    cast('HubSpot does not track close date in property history by default. Add `closedate` to `hubspot__deal_property_history_columns` and full-refresh. Without it, `pushed`, `pulled_in` and `slipped` will all be zero.' as {{ dbt.type_string() }}) as message

{% else %}

select
    cast(null as {{ dbt.type_string() }}) as configured_columns,
    cast(null as {{ dbt.type_string() }}) as message
where false

{% endif %}

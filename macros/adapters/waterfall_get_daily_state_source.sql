{% macro waterfall_get_daily_state_source() %}
{#-
    Dispatches to the adapter selected by `waterfall__history_source`. Every
    adapter must return a SELECT producing exactly the contract's columns
    (see models/intermediate/int_waterfall__daily_state.sql and
    BUILD-PLAN.md §5). Only the Salesforce adapter is implemented in v0.1 --
    the other sources raise a clear compiler error rather than silently
    building nothing, so a misconfigured var fails loudly at compile time
    instead of producing an empty contract.
-#}

{% set history_source = var('waterfall__history_source', 'fivetran_salesforce_history') %}

{% if history_source == 'fivetran_salesforce_history' %}
    {{ return(waterfall_source_fivetran_salesforce()) }}
{% elif history_source == 'fivetran_hubspot_history' %}
    {{ exceptions.raise_compiler_error(
        "waterfall__history_source = 'fivetran_hubspot_history' is not implemented yet (planned for v0.2). See BUILD-PLAN.md §3."
    ) }}
{% elif history_source == 'dbt_snapshot' %}
    {{ exceptions.raise_compiler_error(
        "waterfall__history_source = 'dbt_snapshot' is not implemented yet (planned for v0.3). See BUILD-PLAN.md §3."
    ) }}
{% else %}
    {{ exceptions.raise_compiler_error(
        "Unknown waterfall__history_source: '" ~ history_source ~ "'. Valid values: 'fivetran_salesforce_history' (the only one implemented in v0.1)."
    ) }}
{% endif %}

{% endmacro %}

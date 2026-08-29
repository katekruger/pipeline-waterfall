{% macro waterfall_source_fivetran_salesforce() %}
{#-
    Adapter: fivetran_salesforce_history

    Normalizes fivetran/dbt_salesforce's `salesforce__opportunity_daily_history`
    (v2.4.1+; disabled by default, requires
    `salesforce__opportunity_history_enabled: true`) to the daily-state
    contract. That model's grain is opportunity_day_id, a surrogate key of
    (date_day, opportunity_id).

    Two things handled here, deliberately, and never downstream:

    - source_relation: the Salesforce history model does not carry this
      column (HubSpot's does, for multi-connector union support). Defaulted
      to '' here so the contract's grain key is well-defined across every
      adapter.
    - is_deleted: passed through untouched, never filtered. Dropping deleted
      rows here would make a mid-period soft delete vanish retroactively
      from history, which breaks bridge reconciliation downstream.

    currency_code: Fivetran's `get_opportunity_columns()` does not select
    Salesforce's CurrencyIsoCode by default -- see the multi-currency
    landmine in BUILD-PLAN.md §7. It only appears on the source model when a
    user has added `currency_iso_code` to
    `salesforce__opportunity_pass_through_columns`. This adapter checks for
    the column at compile time and reads it when present, leaving
    currency_code NULL otherwise -- matching "nullable in v0.1" in the
    contract table without needing a dedicated var.
-#}

{% set source_relation = ref('salesforce__opportunity_daily_history') %}
{% set amount_column = var('waterfall__amount_column', 'amount') %}
{% set stage_order_seed = ref(var('waterfall__stage_order_seed', 'waterfall_stage_order')) %}
{% set source_column_names = adapter.get_columns_in_relation(source_relation) | map(attribute='name') | map('lower') | list %}
{% set has_currency_column = 'currency_iso_code' in source_column_names %}

select
    src.opportunity_id as entity_id,
    cast(src.date_day as date) as date_day,
    '' as source_relation,
    src.stage_name as stage,
    stage_order.stage_order as stage_order,
    src.{{ amount_column }} as amount,
    {% if has_currency_column -%}
    src.currency_iso_code as currency_code,
    {%- else -%}
    cast(null as {{ dbt.type_string() }}) as currency_code,
    {%- endif %}
    cast(src.close_date as date) as close_date,
    src.is_closed as is_closed,
    src.is_won as is_won,
    src.owner_id as owner_id,
    cast(src.created_date as date) as created_date,
    src.is_deleted as is_deleted

from {{ source_relation }} as src
left join {{ stage_order_seed }} as stage_order
    on src.stage_name = stage_order.stage

{% endmacro %}

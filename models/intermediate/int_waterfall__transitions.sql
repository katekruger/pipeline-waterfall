{{
    config(
        materialized = 'view'
    )
}}

-- One row per (entity_id, source_relation, period_grain, period_start) for
-- every entity present at period start, period end, or both. Includes rows
-- where movement_bucket is NULL (nothing that affects bridge dollars
-- changed -- see classify_movement.sql and ADR 0002/0003) -- this is the
-- raw comparison layer; waterfall__movement_detail filters to classified
-- rows only. See BUILD-PLAN.md §5 "Movement classification -- the rules".

{% set cohort_mode = var('waterfall__cohort_mode', 'cohort_at_open') %}

with periods as (

    select * from {{ ref('int_waterfall__period_boundaries') }}

),

daily_state as (

    select * from {{ ref('int_waterfall__daily_state') }}

),

{% if cohort_mode == 'current_state' %}
{#-
    current_state: every period is evaluated against the single most
    recent snapshot in the contract, not that period's own period_end. A
    frozen historical period (cohort_at_open) always reports the same
    numbers for January no matter when you run it; current_state re-answers
    "what does today's data say happened in January" every time it's run,
    and will change as later syncs land. This is deliberately the
    higher-blast-radius option -- see ADR 0003.
-#}
{% set latest_query %}
    select cast(max(date_day) as date) as latest_date from {{ ref('int_waterfall__daily_state') }}
{% endset %}
{% if execute and model.resource_type != 'unit_test' and load_relation(ref('int_waterfall__daily_state')) is not none %}
{#- execute alone isn't enough on a cold/empty warehouse -- see ENG-7e.
    The resource_type check is separate (ENG-7b): dbt's unit-test compiler
    swaps every ref() in this model for an injected fixture CTE, but a
    nested run_query() call is NOT rewritten and fails against the real
    relation name. See the identical, more fully commented guard in
    models/preflight/bridge_reconciles.sql and ADR 0007. -#}
    {% set latest_result = run_query(latest_query) %}
    {% set latest_date = latest_result.columns[0].values()[0] %}
{% else %}
    {% set latest_date = '1900-01-01' %}
{% endif %}
{% endif %}

t0_state as (

    select
        p.period_grain,
        p.period_start,
        p.period_end,
        ds.*
    from periods p
    inner join daily_state ds
        on ds.date_day = p.period_start

),

t1_state as (

    select
        p.period_grain,
        p.period_start,
        p.period_end,
        ds.*
    from periods p
    inner join daily_state ds
        {% if cohort_mode == 'current_state' %}
        on ds.date_day = cast('{{ latest_date }}' as date)
        {% else %}
        on ds.date_day = p.period_end
        {% endif %}

),

candidates as (

    select period_grain, period_start, period_end, entity_id, source_relation from t0_state
    union
    select period_grain, period_start, period_end, entity_id, source_relation from t1_state

),

joined as (

    select
        c.period_grain,
        c.period_start,
        c.period_end,
        c.entity_id,
        c.source_relation,

        (t0.entity_id is not null) as exists_t0,
        t0.stage as stage_t0,
        t0.stage_order as stage_order_t0,
        t0.amount as amount_t0,
        t0.currency_code as currency_code_t0,
        t0.close_date as close_date_t0,
        t0.is_closed as is_closed_t0,
        t0.is_won as is_won_t0,
        t0.owner_id as owner_id_t0,

        (t1.entity_id is not null) as exists_t1,
        t1.stage as stage_t1,
        t1.stage_order as stage_order_t1,
        t1.amount as amount_t1,
        t1.currency_code as currency_code_t1,
        t1.close_date as close_date_t1,
        t1.is_closed as is_closed_t1,
        t1.is_won as is_won_t1,
        t1.owner_id as owner_id_t1,
        t1.is_deleted as is_deleted_t1,

        coalesce(t1.created_date, t0.created_date) as created_date,

        -- Generic, bucket-independent pipeline contribution: what this
        -- entity was actually worth to OPEN pipeline at t0/t1. Used to
        -- compute bridge_amount in waterfall__movement_detail -- NOT the
        -- same thing as movement_amount (a business-reporting figure that
        -- can legitimately differ, e.g. 'won' under terminal_wins reports
        -- the full post-growth amount, but only ever removes what was
        -- actually open at t0 from pipeline). Coalesces NULL amounts to 0
        -- rather than propagating NULL through the bridge sum -- see
        -- fixture 18 and ADR 0004. "Pipeline" = is_closed = false only;
        -- is_deleted does not affect this in v0.1 -- see ADR 0004.
        case
            when t0.entity_id is not null and not coalesce(t0.is_closed, false)
                then coalesce(t0.amount, 0)
            else 0
        end as pipeline_contribution_t0,

        case
            when t1.entity_id is not null and not coalesce(t1.is_closed, false)
                then coalesce(t1.amount, 0)
            else 0
        end as pipeline_contribution_t1

    from candidates c
    left join t0_state t0
        on c.period_grain = t0.period_grain
        and c.period_start = t0.period_start
        and c.entity_id = t0.entity_id
        and c.source_relation = t0.source_relation
    left join t1_state t1
        on c.period_grain = t1.period_grain
        and c.period_start = t1.period_start
        and c.entity_id = t1.entity_id
        and c.source_relation = t1.source_relation

)

select
    *,
    {{ classify_movement() }} as movement_bucket
from joined

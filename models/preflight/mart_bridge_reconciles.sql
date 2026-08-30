{{ config(materialized = 'view') }}

-- Restates bridge_reconciles' invariant against the columns a user's chart
-- actually queries -- waterfall__bridge_monthly / waterfall__bridge_quarterly's
-- bridge_amount -- rather than against waterfall__movement_detail directly.
-- ENG-7a found that the bridge marts summed movement_amount, not
-- bridge_amount, so a RevOps user charting the model literally named
-- "bridge" got a number (movement_amount) that has no reconciling
-- property at all. This test exists so that gap can't reopen silently:
-- it fails if the marts' bridge_amount column ever stops tying out to
-- opening/closing pipeline, even if bridge_reconciles (which checks
-- movement_detail, one layer upstream) still passes.
--
-- Opening/closing basis mirrors bridge_reconciles.sql exactly, including
-- the cohort_mode handling -- duplicated rather than shared via a macro
-- for the same reason bridge_reconciles duplicates it from
-- int_waterfall__transitions: this model's whole point is to verify the
-- marts using a code path independent of them.

{% set cohort_mode = var('waterfall__cohort_mode', 'cohort_at_open') %}

with periods as (

    select * from {{ ref('int_waterfall__period_boundaries') }}

),

{% if cohort_mode == 'current_state' %}
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

opening as (

    select
        p.period_grain,
        p.period_start,
        p.period_end,
        sum(coalesce(ds.amount, 0)) as opening_pipeline
    from periods p
    inner join {{ ref('int_waterfall__daily_state') }} ds
        on ds.date_day = p.period_start
    where not coalesce(ds.is_closed, false)
    group by 1, 2, 3

),

closing as (

    select
        p.period_grain,
        p.period_start,
        sum(coalesce(ds.amount, 0)) as closing_pipeline
    from periods p
    inner join {{ ref('int_waterfall__daily_state') }} ds
        {% if cohort_mode == 'current_state' %}
        on ds.date_day = cast('{{ latest_date }}' as date)
        {% else %}
        on ds.date_day = p.period_end
        {% endif %}
    where not coalesce(ds.is_closed, false)
    group by 1, 2

),

mart_movement as (

    select 'month' as period_grain, period_start, sum(bridge_amount) as total_bridge_amount
    from {{ ref('waterfall__bridge_monthly') }}
    group by 1, 2

    union all

    select 'quarter' as period_grain, period_start, sum(bridge_amount) as total_bridge_amount
    from {{ ref('waterfall__bridge_quarterly') }}
    group by 1, 2

),

reconciliation as (

    select
        coalesce(o.period_grain, m.period_grain) as period_grain,
        coalesce(o.period_start, m.period_start) as period_start,
        coalesce(o.opening_pipeline, 0) as opening_pipeline,
        coalesce(c.closing_pipeline, 0) as closing_pipeline,
        coalesce(m.total_bridge_amount, 0) as total_bridge_amount,
        coalesce(o.opening_pipeline, 0) + coalesce(m.total_bridge_amount, 0) as computed_closing_pipeline,
        coalesce(c.closing_pipeline, 0) - (coalesce(o.opening_pipeline, 0) + coalesce(m.total_bridge_amount, 0)) as delta
    from opening o
    full outer join closing c
        on o.period_grain = c.period_grain and o.period_start = c.period_start
    full outer join mart_movement m
        on coalesce(o.period_grain, c.period_grain) = m.period_grain
        and coalesce(o.period_start, c.period_start) = m.period_start

)

select
    period_grain,
    period_start,
    opening_pipeline,
    closing_pipeline,
    total_bridge_amount,
    computed_closing_pipeline,
    delta,
    'Period ' || cast(period_start as varchar) || ' (' || period_grain || ') bridge_amount in the '
        || period_grain || 'ly mart does not reconcile: opening ' || cast(opening_pipeline as varchar)
        || ' + bridge_amount ' || cast(total_bridge_amount as varchar) || ' = '
        || cast(computed_closing_pipeline as varchar) || ', but closing pipeline is '
        || cast(closing_pipeline as varchar) || ' (delta ' || cast(delta as varchar) || ').' as message
from reconciliation
where delta != 0

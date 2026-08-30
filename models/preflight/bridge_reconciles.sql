{{ config(materialized = 'view') }}

-- THE HEADLINE TEST. Fires when, for any period, opening pipeline + every
-- movement bucket does not EXACTLY equal closing pipeline. Not within a
-- tolerance.
--
-- Opening/closing pipeline are computed directly from
-- int_waterfall__daily_state here -- independently of
-- waterfall__movement_detail's bridge_amount -- so this test can actually
-- catch a real bug in classify_movement, rather than just checking its own
-- math against itself. "Pipeline" = open (is_closed = false); this package
-- does not exclude is_deleted from pipeline totals in v0.1 -- see ADR 0004.
--
-- t1's date basis mirrors int_waterfall__transitions' cohort_mode handling
-- exactly (period_end under cohort_at_open, the single latest date_day
-- under current_state) -- duplicated rather than shared via a macro,
-- deliberately: this model's whole point is to verify the bridge using a
-- code path independent of transitions/movement_detail, so the date-basis
-- logic needs to actually be reproduced here, not just inherited.

{% set cohort_mode = var('waterfall__cohort_mode', 'cohort_at_open') %}

with periods as (

    select * from {{ ref('int_waterfall__period_boundaries') }}

),

{% if cohort_mode == 'current_state' %}
{% set latest_query %}
    select cast(max(date_day) as date) as latest_date from {{ ref('int_waterfall__daily_state') }}
{% endset %}
{% if execute and model.resource_type != 'unit_test' and load_relation(ref('int_waterfall__daily_state')) is not none %}
{#- execute alone isn't enough on a cold/empty warehouse -- see ENG-7e and
    the identical guard in int_waterfall__period_boundaries.sql. The
    resource_type check is separate and load-bearing for a different
    reason (ENG-7b): dbt's unit-test compiler swaps every ref() in this
    model for an injected fixture CTE, but a nested run_query() call is
    NOT rewritten the same way and fails against the real relation name.
    Every unit_test in models/preflight/schema.yml supplies its own
    period_boundaries/daily_state fixtures directly via `given:` and
    doesn't exercise current_state semantics regardless of what
    waterfall__cohort_mode happens to be set to for the invocation as a
    whole -- so falling back to the sentinel here is safe for every
    unit_test that exists today. A future unit_test that specifically
    needs to exercise current_state's live-latest-date behavior can't be
    written against this model as-is; see ADR 0007. -#}
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

movements as (

    select
        period_grain,
        period_start,
        sum(bridge_amount) as total_movement
    from {{ ref('waterfall__movement_detail') }}
    group by 1, 2

),

reconciliation as (

    select
        coalesce(o.period_grain, m.period_grain) as period_grain,
        coalesce(o.period_start, m.period_start) as period_start,
        coalesce(o.opening_pipeline, 0) as opening_pipeline,
        coalesce(c.closing_pipeline, 0) as closing_pipeline,
        coalesce(m.total_movement, 0) as total_movement,
        coalesce(o.opening_pipeline, 0) + coalesce(m.total_movement, 0) as computed_closing_pipeline,
        coalesce(c.closing_pipeline, 0) - (coalesce(o.opening_pipeline, 0) + coalesce(m.total_movement, 0)) as delta
    from opening o
    full outer join closing c
        on o.period_grain = c.period_grain and o.period_start = c.period_start
    full outer join movements m
        on coalesce(o.period_grain, c.period_grain) = m.period_grain
        and coalesce(o.period_start, c.period_start) = m.period_start

)

select
    period_grain,
    period_start,
    opening_pipeline,
    closing_pipeline,
    total_movement,
    computed_closing_pipeline,
    delta,
    'Period ' || cast(period_start as varchar) || ' (' || period_grain || ') does not reconcile: opening '
        || cast(opening_pipeline as varchar) || ' + movements ' || cast(total_movement as varchar)
        || ' = ' || cast(computed_closing_pipeline as varchar) || ', but closing pipeline is '
        || cast(closing_pipeline as varchar) || ' (delta ' || cast(delta as varchar) || ').' as message
from reconciliation
where delta != 0

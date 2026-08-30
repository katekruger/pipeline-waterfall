{{ config(materialized = 'view') }}

-- Fires when waterfall__created_stage_filter is set AND excludes an
-- entity that classify_movement's 'created' branch would otherwise have
-- classified this period (ENG-7c, ADR 0008).
--
-- created_stage_filter only controls which newly-created entities land in
-- the 'created' bucket -- it has no effect on int_waterfall__daily_state,
-- which has no concept of the filter at all. A filtered-out entity is
-- still present, open, and counted in closing pipeline; it just has no
-- 'created' movement row to explain how it got there. bridge_reconciles
-- and mart_bridge_reconciles will correctly fail for exactly this reason
-- (their delta will equal the excluded entity's amount), but with no
-- indication that created_stage_filter is the cause -- this test names it
-- directly, the same way every other preflight test in this package does.
--
-- Computed independently off int_waterfall__transitions' raw columns
-- (not off waterfall__movement_detail or classify_movement's own logic),
-- so a bug in the filter's SQL inside classify_movement itself couldn't
-- also hide it from this check. ref() is left unconditional (a WHERE
-- clause, not a Jinja conditional wrapping the whole query, is what makes
-- this a no-op when the var is unset) so dbt always records the
-- dependency on int_waterfall__transitions -- an earlier version wrapped
-- the entire query in a Jinja conditional on created_stage_filter's
-- length, which meant the ref() was never parsed under the default
-- (empty) var and dbt had no edge forcing int_waterfall__transitions to
-- build first, breaking build ordering for this model's own unit test.

{% set created_stage_filter = var('waterfall__created_stage_filter', []) %}

with transitions as (

    select * from {{ ref('int_waterfall__transitions') }}

),

excluded_creates as (

    select
        entity_id,
        period_grain,
        period_start,
        stage_t1,
        amount_t1
    from transitions
    where
        {% if created_stage_filter | length > 0 %}
        not exists_t0
        and exists_t1
        and not coalesce(is_closed_t1, false)
        and created_date >= period_start and created_date < period_end
        and stage_t1 not in ({{ "'" ~ created_stage_filter | join("', '") ~ "'" }})
        {% else %}
        false
        {% endif %}

)

select
    entity_id,
    period_grain,
    period_start,
    stage_t1 as excluded_stage,
    amount_t1 as amount,
    'Entity ' || entity_id || ' was created in period ' || cast(period_start as varchar)
        || ' (' || period_grain || ') in stage ''' || stage_t1
        || ''', which waterfall__created_stage_filter excludes from the ''created'' bucket. '
        || 'It is still open and counted in closing pipeline (amount ' || cast(amount_t1 as varchar)
        || '), so the bridge will not reconcile for this period. Either add '''
        || stage_t1 || ''' to waterfall__created_stage_filter, or unset it -- excluding a stage '
        || 'from ''created'' without also excluding it from pipeline totals is a known v0.1 '
        || 'limitation. See ADR 0008.' as message
from excluded_creates

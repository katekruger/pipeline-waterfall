-- Fails if any of the 20 canonical fixtures (see
-- integration_tests/seeds/salesforce__opportunity_daily_history.csv and the
-- edge-case checklist in the prompts doc) doesn't land in its documented
-- expected bucket for the January 2026 monthly period. Expected NULL means
-- "no row in waterfall__movement_detail":
--   - fixture 14 (stage regression) -- ADR 0002
--   - fixtures 15/17/19/20 (soft delete, history gap, unmapped stage,
--     currency) -- these exercise the contract (Prompt 1) or preflight
--     (Prompt 3), not classification; nothing in the ten buckets checks
--     is_deleted, and NULL stage_order / unchanged fields correctly fail
--     every predicate rather than false-matching one -- see ADR 0003
--   - fixture 18 (amount -> NULL) -- SQL's three-valued logic means NULL
--     comparisons fail both expanded and contracted safely rather than
--     crashing or false-matching

with expected as (

    select * from (
        values
            ('case01-simple-win-1', 'won'),
            ('case02-simple-loss-1', 'lost'),
            ('case03-created-open-1', 'created'),
            ('case04-created-and-won-1', 'won'),
            ('case05-pushed-1', 'pushed'),
            ('case06-pulled-in-1', 'pulled_in'),
            ('case07-slipped-1', 'slipped'),
            ('case08-advanced-1', 'advanced'),
            ('case09-expanded-1', 'expanded'),
            ('case10-contracted-1', 'contracted'),
            ('case11-reopened-1', 'reopened'),
            ('case12-expand-and-won-1', 'won'),
            ('case13-pushed-and-expanded-1', 'pushed'),
            ('case14-stage-regression-1', null),
            ('case15-soft-deleted-1', null),
            ('case16-merged-away-1', 'lost'),
            ('case16-merged-survivor-1', 'expanded'),
            ('case17-gappy-history-1', null),
            ('case18-amount-null-1', null),
            ('case19-unknown-stage-1', null),
            ('case20-currency-usd-1', null),
            ('case20-currency-eur-1', null)
    ) as t (entity_id, expected_bucket)

),

actual as (

    select entity_id, movement_bucket
    from {{ ref('waterfall__movement_detail') }}
    where period_grain = 'month' and period_start = cast('2026-01-01' as date)

)

select
    e.entity_id,
    e.expected_bucket,
    a.movement_bucket as actual_bucket
from expected e
left join actual a using (entity_id)
where a.movement_bucket is distinct from e.expected_bucket

-- Fails if any of the 20 canonical fixtures (see
-- integration_tests/seeds/salesforce__opportunity_daily_history.csv and the
-- edge-case checklist in the prompts doc) doesn't land in its documented
-- expected bucket for the January 2026 monthly period. Expected NULL means
-- "no row in waterfall__movement_detail":
--   - fixture 14 (stage regression) -- ADR 0002
--   - fixture 15 (soft delete) and fixture 20 (currency) -- these exercise
--     the contract (Prompt 1), not classification; nothing in the ten
--     buckets checks is_deleted, and a currency-only fixture has no
--     amount/stage/close_date change to classify -- see ADR 0002/0003
--
-- Fixtures 17 (gappy history) and 19 (unknown stage) are no longer in the
-- standing seed as of Prompt 3 -- once models/preflight/history_gap.sql and
-- stage_order_complete.sql exist, their broken characteristic would fail
-- THIS build rather than merely being unclassified. They're re-proven as
-- deliberately-broken unit_tests in models/preflight/schema.yml instead --
-- see ADR 0004 and the Prompt 3 PR body for the full reasoning.
--
-- Fixture 18 (amount -> NULL) reclassifies as of Prompt 3: NULL amounts are
-- now coalesced to 0 in classify_movement.sql, so a NULL amount on a
-- previously-nonzero deal is a real contraction (its pipeline contribution
-- genuinely dropped to nothing) rather than falling through unclassified --
-- see ADR 0004.

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
            ('case18-amount-null-1', 'contracted'),
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

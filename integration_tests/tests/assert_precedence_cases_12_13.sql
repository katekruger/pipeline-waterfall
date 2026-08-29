-- BUILD-PLAN.md §5 precedence: terminal > reopened > date movement >
-- advanced > amount movement. Fixtures 12 and 13 are built specifically to
-- prove it: a deal that both grew AND won lands in 'won' (not 'expanded'),
-- and a deal that both grew AND had its close_date pushed lands in
-- 'pushed' (not 'expanded'). Checking the dollar amount, not just the
-- bucket label, is what actually proves the increment is absorbed under
-- the default waterfall__amount_change_precedence = 'terminal_wins' -- a
-- bucket-only check could pass even if the amount were wrong.

with actual as (

    select entity_id, movement_bucket, movement_amount
    from {{ ref('waterfall__movement_detail') }}
    where period_grain = 'month' and period_start = cast('2026-01-01' as date)

),

expected as (

    select * from (
        values
            ('case12-expand-and-won-1', 'won', 13000.0),
            ('case13-pushed-and-expanded-1', 'pushed', 11000.0)
    ) as t (entity_id, expected_bucket, expected_amount)

)

select
    e.entity_id,
    e.expected_bucket,
    a.movement_bucket as actual_bucket,
    e.expected_amount,
    a.movement_amount as actual_amount
from expected e
left join actual a using (entity_id)
where a.movement_bucket is distinct from e.expected_bucket
   or a.movement_amount is distinct from e.expected_amount

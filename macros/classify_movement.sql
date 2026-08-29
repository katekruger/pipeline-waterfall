{% macro classify_movement() %}
{#-
    Emits a CASE WHEN expression classifying one entity-period comparison
    row into exactly one of the ten movement buckets, or NULL if nothing
    that affects bridge dollars changed (see ADR 0002 and ADR 0003).

    Expects these columns to already be in scope wherever this macro is
    used (built by int_waterfall__transitions.sql):

      exists_t0, exists_t1,
      is_closed_t0, is_won_t0, close_date_t0, stage_order_t0, amount_t0,
      is_closed_t1, is_won_t1, close_date_t1, stage_order_t1, amount_t1, stage_t1,
      created_date, period_start, period_end

    Precedence (BUILD-PLAN.md §5, load-bearing):
      terminal (won/lost) > reopened > date movement (pushed/pulled_in/slipped)
        > advanced > amount movement (expanded/contracted) > created

    'created' is evaluated last here even though it isn't part of the
    documented precedence list -- the list only orders buckets that can
    actually conflict with each other, and 'created' never can: every other
    bucket requires exists_t0 (an entity created this period has no t0 row),
    except terminal (won/lost), which is defined below to fire even when
    exists_t0 is false. That's deliberate, not an oversight -- it's what
    correctly classifies fixture 4 (created AND won in the same period) as
    'won' instead of silently falling through, which is exactly the
    "easy to miss" landmine that fixture calls out. See ADR 0003.
-#}

{% set slippage_definition = var('waterfall__slippage_definition', 'close_date_period') %}
{% set created_stage_filter = var('waterfall__created_stage_filter', []) %}

case

    -- terminal: won. Absence at t0 counts as "not won", so a deal that's
    -- created and won inside the same period still lands here (fixture 4).
    when coalesce(is_won_t1, false) and not coalesce(is_won_t0, false)
        then 'won'

    -- terminal: lost. Same absence-as-false treatment, though every
    -- current fixture that hits this also exists at t0.
    when coalesce(is_closed_t1, false) and not coalesce(is_won_t1, false)
        and not coalesce(is_closed_t0, false)
        then 'lost'

    -- reopened: must be checked before date/amount movement, and must NOT
    -- fold into 'created' -- both would overstate pipeline generation or
    -- misrepresent a real reopen as brand new (fixture 11).
    when coalesce(is_closed_t0, false) and not coalesce(is_closed_t1, false)
        then 'reopened'

    {% if slippage_definition == 'close_date_period' %}
    -- pushed: open at both, close_date was in-period at t0 and moved to on
    -- or after this period's end (fixture 5).
    when exists_t0 and exists_t1
        and not coalesce(is_closed_t0, false) and not coalesce(is_closed_t1, false)
        and close_date_t0 >= period_start and close_date_t0 < period_end
        and close_date_t1 >= period_end
        then 'pushed'
    {% endif %}

    -- pulled_in: the mirror of pushed -- close_date was NOT in-period at t0
    -- (specifically, in a later period) and moved into this period
    -- (fixture 6). Tracked the same way under both slippage definitions --
    -- BUILD-PLAN.md §5 only exposes a house choice for pushed vs. slipped,
    -- not for pulled_in, which isn't contested the same way.
    when exists_t0 and exists_t1
        and not coalesce(is_closed_t0, false) and not coalesce(is_closed_t1, false)
        and close_date_t0 >= period_end
        and close_date_t1 >= period_start and close_date_t1 < period_end
        then 'pulled_in'

    {% if slippage_definition == 'close_date_period' %}
    -- slipped: close_date was in-period at t0, period ended with it still
    -- open (fixture 7).
    when exists_t0 and exists_t1
        and not coalesce(is_closed_t0, false) and not coalesce(is_closed_t1, false)
        and close_date_t0 >= period_start and close_date_t0 < period_end
        then 'slipped'
    {% else %}
    -- period_end_open: Saber's glossary collapses pushed and slipped into
    -- one category (BUILD-PLAN.md §5) -- under this definition, any deal
    -- open at both boundaries that didn't get pulled in counts as
    -- 'slipped', whether or not its close_date moved. Fixture 5, which is
    -- 'pushed' under the default definition, is 'slipped' under this one --
    -- see the dedicated test.
    when exists_t0 and exists_t1
        and not coalesce(is_closed_t0, false) and not coalesce(is_closed_t1, false)
        then 'slipped'
    {% endif %}

    -- advanced: open at both, stage_order strictly increased, close_date
    -- unchanged (fixture 8). A stage_order decrease (fixture 14) falls
    -- through unclassified -- ADR 0002, not a bug.
    when exists_t0 and exists_t1
        and not coalesce(is_closed_t0, false) and not coalesce(is_closed_t1, false)
        and stage_order_t1 > stage_order_t0
        and close_date_t1 = close_date_t0
        then 'advanced'

    -- expanded / contracted: open at both, amount moved and nothing higher
    -- in precedence claimed the row (fixtures 9, 10; fixtures 12 and 13 are
    -- claimed by won/pushed respectively before reaching here). Amounts
    -- are coalesced to 0 for the comparison -- an amount going to NULL
    -- (fixture 18) is a real contraction (its pipeline contribution really
    -- did drop to nothing), and NULL > / < a number is NULL (not true) in
    -- SQL, which would otherwise let this fall through unclassified even
    -- though its bridge_amount is genuinely nonzero. See ADR 0004.
    when exists_t0 and exists_t1
        and not coalesce(is_closed_t0, false) and not coalesce(is_closed_t1, false)
        and coalesce(amount_t1, 0) > coalesce(amount_t0, 0)
        then 'expanded'

    when exists_t0 and exists_t1
        and not coalesce(is_closed_t0, false) and not coalesce(is_closed_t1, false)
        and coalesce(amount_t1, 0) < coalesce(amount_t0, 0)
        then 'contracted'

    -- created: absent at t0, present and open at t1, created within the
    -- period. Deliberately last -- an entity that's absent at t0 but wins
    -- or loses within the period is claimed by the terminal checks above
    -- first, not here (fixture 4).
    when not exists_t0 and exists_t1
        and not coalesce(is_closed_t1, false)
        and created_date >= period_start and created_date < period_end
        {% if created_stage_filter | length > 0 -%}
        and stage_t1 in ({{ "'" ~ created_stage_filter | join("', '") ~ "'" }})
        {%- endif %}
        then 'created'

    else null
end

{% endmacro %}

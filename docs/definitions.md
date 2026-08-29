# Definitions

Every genuinely contested definition in this package, both options, and the consequence of picking each. Forward this to whoever needs to trust the number — a CFO, a board, a RevOps lead inheriting someone else's dashboard.

None of these are settled questions in the industry. Where a definition is arbitrary, that's stated plainly rather than dressed up as a standard. Where practitioners disagree, both sides are named, not just the one this package defaults to.

## Pushed vs. slipped

**The contested question:** a deal is still open past when it was supposed to close. Is that "pushed," "slipped," or something else — and are they even different things?

There is no industry consensus here. [Saber's own glossary](https://www.saber.app/glossary/pipeline-waterfall-analysis) collapses pushed and slipped into a single category, which is itself evidence that practitioners don't agree on a split. [ORM's guide to deal slippage](https://orm-tech.com/blog/how-to-calculate-deal-slippage-rate) treats "slippage" as the umbrella term for any deal that didn't close on time, without further subdividing it.

This package ships two definitions, controlled by `waterfall__slippage_definition`:

- **`close_date_period`** (default): three separate buckets, keyed on which *period* the close date falls into. `pushed` — the close date was inside this period at the start and moved to on/after this period's end. `pulled_in` — the mirror: the close date was beyond this period at the start and moved into it. `slipped` — the close date stayed inside this period, but the deal is still open at period end (it simply didn't close on time).
- **`period_end_open`**: the Saber-style collapse. Anything that would be `pushed` under the other definition is instead called `slipped` — the practical distinction between "moved to next period" and "just didn't close" disappears. `pulled_in` is unaffected either way — it isn't contested the same way pushed-vs-slipped is.

**Consequence of each:** `close_date_period` gives you a sharper signal — "the close date physically moved" is a different rep behavior than "the close date stayed put and the deal just didn't close" — but it's a house-specific split nobody else is guaranteed to use the same way. `period_end_open` is more portable across orgs and matches how some practitioners already talk about slippage, at the cost of losing that distinction.

## Cohort-at-open vs. current-state

**The single variable that most changes the reported number** (see BUILD-PLAN.md §5). Controlled by `waterfall__cohort_mode`.

- **`cohort_at_open`** (default): every period's closing snapshot is that period's *own* period-end date. Re-running a report on January always returns the same numbers, no matter when you run it — it's a frozen historical view.
- **`current_state`**: every period's closing snapshot is the single most recent date in your data, not that period's own end. Reporting on January after March's data has landed compares January's opening cohort against *March's* state. Re-running the same "January" report next month can produce a different answer than it did this month.

**Consequence of each:** `cohort_at_open` is what you want for historical, auditable reporting — a board deck from Q1 shouldn't silently change numbers in Q3. `current_state` is what you want if the question is "what actually happened to the deals that were open in January, as best we know today" — useful for post-mortems, less useful for a number that needs to stay stable once reported.

## Created: all opportunities vs. qualified only

**The contested question:** does "created" mean the record was inserted, or that a rep actually qualified it?

Fivetran's own `sales_snapshot` model counts all open opportunities, full stop. [David Sacks' framework for pipeline metrics](https://sacks.substack.com/p/the-pipeline-metrics-that-matter) instead defines an opportunity as created when a rep qualifies a lead — meaning plenty of CRM records that exist don't count as "created" pipeline yet.

`waterfall__created_stage_filter` controls this: an empty list (the default) counts every opportunity, regardless of stage, as soon as it appears open. A non-empty list of stage names restricts `created` to opportunities that reach one of those stages within the period.

**Consequence of each:** the default (all opportunities) will overstate pipeline generation for any mature org that has a real qualification gate — a lead a rep hasn't touched yet still counts. Restricting to specific stages is more accurate for most B2B sales motions, but it's a decision this package cannot make for you: which stage counts as "qualified" varies by org and isn't discoverable from the data. Defaulting to "all" is a deliberate choice to be wrong in a documented, correctable direction rather than silently assume a stage taxonomy this package has no way to know.

## Amount attribution when a deal both grows and closes

**The contested question:** a deal is $10,000 at the start of the period, grows to $13,000, and closes won — all in the same period. Is the win worth $10,000 or $13,000?

Controlled by `waterfall__amount_change_precedence`:

- **`terminal_wins`** (default): the win is reported at the full $13,000 — the growth is absorbed into the terminal event. This is the intuitive answer for sales reporting: "we won a $13k deal."
- **`movement_wins`**: the terminal bucket's reported amount reverts to the pre-growth $10,000 instead. **Scope note:** this does not additionally emit a separate `expanded` line for the $3,000 delta — the growth simply isn't attributed to `won` under this mode, it's not attributed anywhere else either. A future version that wants to split the two apart as separate line items would need its own change.

**Consequence of each:** these two numbers genuinely diverge, and neither is "the pipeline delta." The bridge (`bridge_reconciles`) doesn't use either of them — it sums a separate, generic `bridge_amount` that's always exactly what left or entered open pipeline, regardless of which reporting convention you've chosen. `movement_amount` (what `waterfall__amount_change_precedence` controls) is purely a business-reporting figure layered on top; changing it never affects whether the bridge reconciles.

## Reopened deals

**The contested question:** a deal was closed-lost, then reopened. Is that a new deal ("created"), or something else?

This package's answer is not contested — it's a correctness requirement, not a house opinion. Folding a reopen into `created` overstates how much *new* pipeline was actually generated that period; the deal already existed, it just came back. `reopened` is its own bucket, checked ahead of `pushed`/`pulled_in`/`slipped` in precedence, specifically so a reopen is never miscategorized as a date movement either.

## Multi-currency

Fivetran's Salesforce package has **zero** currency handling — no `CurrencyIsoCode`, no conversion, nothing, even for orgs with Multiple Currencies enabled in Salesforce. Amounts across currencies are being summed today unless you're explicitly guarding against it. `multi_currency_unguarded` fails the build the moment more than one `currency_code` shows up in your contract and `waterfall__currency_mode` isn't set — nobody else catches this.

Real currency conversion (record currency, corporate currency at close, corporate currency as-of-snapshot) is v0.2 scope — not yet built. `waterfall__currency_mode` today is an acknowledgment flag, not a conversion feature: setting it silences the preflight check, it does not convert anything. Do not set it as a way to make the check pass without deciding what you actually want to happen to a multi-currency amount total — that decision doesn't exist in this package yet.

## Fiscal vs. calendar periods

Not yet supported — `waterfall__fiscal_periods` exists as a reserved var but v0.1 always uses calendar month/quarter boundaries. Salesforce exposes `fiscal_quarter`/`fiscal_year`/`fiscal` fields; most B2B orgs report on fiscal, not calendar, periods. This is a known, acknowledged gap for v0.2, not a design position that calendar periods are correct — they're just what's built today.

## Why `pulled_in` has to exist

Not contested, but easy to underestimate: `pulled_in` (a deal's close date moves to an *earlier* period) is the arithmetic mirror of `pushed`. Without it, the bridge cannot reconcile — every pushed deal moves dollars forward in time, and if nothing ever moves them backward, the math only works in one direction. A package that models `pushed` without `pulled_in` will look correct in the common case and quietly fail to reconcile the first time a rep pulls a close date in instead of out.

## Sources

- [Saber — Pipeline Waterfall Analysis](https://www.saber.app/glossary/pipeline-waterfall-analysis)
- [ORM — How to Calculate Deal Slippage Rate](https://orm-tech.com/blog/how-to-calculate-deal-slippage-rate)
- [David Sacks — The Pipeline Metrics That Matter](https://sacks.substack.com/p/the-pipeline-metrics-that-matter)
- [Equals — Pipeline Movement Waterfall](https://equals.com/use-cases/pipeline-movement-waterfall/)

See `BUILD-PLAN.md` §12 for the complete source list, including the Fivetran and Salesforce documentation this package's adapter and preflight behavior are built against.

# Postmortem: order lines and payments arrive one night before their order

> Blameless: describe what the SYSTEM allowed to happen, not who made a mistake.

| | |
|---|---|
| Date of incident | 2026-10-24 (found); recurring every night by design |
| Authors | Ahmed Nabil, Mohamed Mosaad |
| Severity | SEV-3 (last hour of each day is one night late; no data wrong or lost) |

## 1. Summary
Every night, the order lines and payments of orders placed in the last hour of the Cairo
day (about 23:00 to 23:59) are loaded into Bronze, but their orders are not. The orders
arrive with the next night's load. For one night these lines and payments are "orphans":
they have no matching order in `silver_orders`. Nothing is lost and no number is wrong
in the end, but "yesterday's" order-based numbers are about 2 to 4% low until the next
nightly run corrects them.

## 2. Impact
- **Late:** in `silver_orders`, the orders placed in the last hour of the previous day
  (2026-10-23: 216 orders). Their 634 lines in `silver_order_items` and 151 payments in
  `silver_payments` are flagged `is_orphan = true` and left out of order-based joins. Any gold
  number for "yesterday" built from orders (revenue, number of orders, average basket) is
  low by about 100 to 250 orders until the next night.
- **Wrong or lost:** nothing.
  - The orphan rows are kept in silver, only flagged.
  - Orphans from earlier days are gone: the first counts (about 179 lines and 129 payments)
    resolved after the next load. So the orders do arrive.
  - The 216 orphan orders are missing from `bronze_app.orders` in every version, while
    orders with nearby IDs are there: a timing gap, not a filter in our models.

## 3. Timeline (Cairo time)
| Time | Event |
|---|---|
| ~2026-10-19 | First seen: `relationships` test on `order_items.order_id` warns about ~179 missing orders; set to `warn` and marked "revisit later" in `source.yml` |
| 2026-10-23 | `silver_payments` relationship test warns: 129, later 151 orphan payments |
| 2026-10-24 ~21:20 | `silver_order_items` relationship test warns: 634 orphan lines; investigation starts |
| 2026-10-24 ~21:30 | Found: all orphans are from 2026-10-23 23:02 to 23:59, none of their orders exist in Bronze, older orphans are gone; root cause identified in the loader's day assignment |
| _next morning_ | Verify: the 216 orders of 2026-10-23 are loaded and a new tail from 2026-10-24 23:00 to 23:59 appears |

## 4. Detection
Detected by the dbt `relationships` tests on `silver_order_items.order_id` and
`silver_payments.order_id` (severity `warn`). They warned from the first silver build, but
the growing count (179, then 634) is what triggered the investigation.

What would have explained it sooner: grouping the orphans by Cairo day and hour (query in
section 6) instead of looking at the total count only.

## 5. Root cause and contributing factors
**Root cause:** the source database keeps only the **current** version of each row, and our
loader (`ingestion/database/Ingest_app.py`) assigns a row to the Cairo day of its last change,
`coalesce(updated_at, created_at)`.

Example: an order placed at 23:30 on day D and delivered at 00:20 on day D+1.

| Table | `updated_at` in the source when we load D | Loaded with day |
|---|---|---|
| `order_items` | D 23:30 (lines never change) | D |
| `payments` | D 23:30 | D |
| `orders` | D+1 00:20 (status changed to `delivered`) | **D+1** |

**Five whys:**
1. Why do lines and payments have no order? Because the order was not loaded with day D.
2. Why was it not loaded with day D? Because its last change (delivery) happened on D+1, and
   the loader picks rows by the day of their last change.
3. Why don't we load the earlier "placed" version? Because the source only stores the current
   row, so the "placed at 23:30" version no longer exists when D is loaded.
4. Why do only the last-hour orders have this problem? Delivery takes under an hour, so only orders placed
   late in the evening are delivered after midnight.
5. Why did it look like a growing problem? We compared totals on different days; each count
   was a new day's tail, not an accumulation.

**Contributing factor:** the load is correct by design (idempotent, loads finished days only),
so there was no error to alert on; only a data test could show it.

## 6. Recovery
No manual recovery is needed: the next nightly load brings the missing orders, and silver and
gold are rebuilt as full tables every night, so the day is corrected automatically.

How to verify every morning (orphans must come only from the previous Cairo day, between
about 23:00 and 23:59, and disappear after the next load):

```sql
select toDate(created_at, 'Africa/Cairo') as day,
       count() as lines,
       uniqExact(order_id) as orders,
       min(created_at), max(created_at)
from silver_app.silver_order_items
where is_orphan
group by day
order by day
```

If orphans appear on older days, or outside the last hour of a day, this is a different
problem (orders really missing) and must be investigated.

## 7. What went well / what went badly / where we got lucky
**Went well**
- The `relationships` tests were set to `warn` and kept the issue visible without stopping
  the pipeline.
- Silver flags orphans (`is_orphan`) instead of dropping them, so nothing is lost.
- The loader is idempotent, so the late orders arrive without any manual fix.

**Went badly**
- The warning was marked "revisit later" for several days before anyone investigated.
- We first read the growing count as a growing problem, because we compared totals from
  different days.

**Where we got lucky**
- Deliveries take under an hour, so the effect is limited to the last hour of the day.

## 8. Action items
| # | Action | Prevent / detect / mitigate | Owner | Priority |
|---|---|---|---|---|
| 1 | Keep the `relationships` tests on `order_id` at `warn` and check the orphan query every morning | Detect | Ahmed Nabil | High |
| 2 | Build gold revenue/orders from orders joined to their lines, rebuilt as `table` every night, so late orders are included automatically | Mitigate | Mohamed Mosaad | High |
| 3 | Add a singular test that fails if any orphan is older than the previous Cairo day (turns "late" into an alert only when it is really "missing") | Detect | Ahmed Nabil | Medium |
| 4 | Loader option (postponed): when loading day D, also extract rows **created** on D even if changed later; requires `existing_versions` to check more than the D partition, because those versions belong to D+1 | Prevent | Mohamed Mosaad | Low |

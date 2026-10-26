# Postmortem: duplicated payments in the source database

> Blameless: describe what the SYSTEM allowed to happen, not who made a mistake.

| | |
|---|---|
| Date of incident | _TBD_ (first duplicated payment, see query in section 6); found while building `silver_payments` |
| Authors | Ahmed Nabil, Mohamed Mosaad |
| Severity | SEV-2 (would make cash collected WRONG if not removed; caught before gold) |

## 1. Summary
The source table `app.payments` contains payments recorded twice. Each duplicate pair has the
same order, status, method and amount, payment IDs exactly 1 apart, and timestamps exactly
2 seconds apart. This affects 886 paid and 99 refunded payments (985 extra rows), all on the
most recent orders (order IDs 3,533,409 to 3,550,885). The pattern points to a retry in the
company's payment system, not to real repeated charges (this is an inference from the
pattern, not confirmed by the company). We remove the duplicates in silver, so no published
number was wrong.

## 2. Impact
- **Wrong (if not handled):** summing `bronze_app.payments.amount` would overstate cash
  collected by the amount of the 886 duplicated paid rows, and refunds by the 99 duplicated
  refunded rows (amounts: see query in section 6).
- **Handled:** `silver_payments` keeps one row per (order, status, method, amount), the lowest
  `payment_id`, so silver and gold are correct.
- **Lost:** nothing. Bronze keeps every row as received.

## 3. Timeline (Cairo time)
| Time | Event |
|---|---|
| _TBD_ | First duplicated payment created in the source (query in section 6) |
| _TBD (before 2026-10-24)_ | Detected during the payments EDA: groups with the same order / status / method / amount |
| _TBD_ | Pattern analysed: all 985 pairs have IDs 1 apart and timestamps 2 s apart; no genuine repeat charge found |
| _TBD_ | `silver_payments` built with deduplication and test `silver_payments_no_duplicates` |

## 4. Detection
Detected by the EDA on payments before writing the silver model, not by an alert.
What detects it from now on: the singular test `tests/app/payments/silver_payments_no_duplicates.sql`
(fails if silver still has two payments with the same order / status / method / amount).
A Bronze-level warn test counting new duplicate pairs per day would show if the source bug grows.

## 5. Root cause and contributing factors
**Root cause (outside our control):** the company's payment system stores some payments twice,
2 seconds apart (likely a retry that does not check whether the first attempt succeeded).

**Five whys:**
1. Why would cash collected be too high? Some payments exist twice.
2. Why twice? The source inserted a second identical row 2 seconds after the first.
3. Why does that reach us? Our loader copies the source as received (by design, Bronze is raw).
4. Why could it reach gold? Only if silver does not deduplicate payments.
5. Why is deduplication tricky? Payments have no business key: we must infer "same payment"
   from order, status, method and amount.

**Contributing factor:** the deduplication rule would also merge a genuine second identical
payment for the same order (none found today, but possible).

## 6. Recovery
Changes made:
- `models/silver/app/silver_payments.sql`: `limit 1 by order_id, payment_status, payment_method, amount`
  ordered by `payment_id` (keeps the first of each pair).
- Test `silver_payments_no_duplicates` (error) and `silver_payments_amounts` (error).

Queries to complete this report (run in DataGrip):
```sql
-- first and last duplicated payment, and the extra amount
select
    min(created_at) as first_duplicate,
    max(created_at) as last_duplicate,
    count() as extra_rows,
    sumIf(amount, payment_status = 'paid') as extra_paid_amount,
    sumIf(amount, payment_status = 'refunded') as extra_refunded_amount
from bronze_app.payments
where payment_id not in (select payment_id from silver_app.silver_payments)
  and order_id not in (select order_id from bronze_app.orders where customer_id = 150003)
```

## 7. What went well / what went badly / where we got lucky
**Went well**
- Found during EDA, before any gold number was published.
- The pattern (IDs 1 apart, 2 seconds apart) made the duplicates easy to prove.

**Went badly**
- No automatic check at Bronze level; detection depended on doing the EDA.

**Where we got lucky**
- Every duplicate follows the same signature, so a simple rule removes them all.

## 8. Action items
| # | Action | Prevent / detect / mitigate | Owner | Priority |
|---|---|---|---|---|
| 1 | Deduplicate in `silver_payments` + test `silver_payments_no_duplicates` (done) | Mitigate | Ahmed Nabil | High |
| 2 | Tighten the rule: only merge rows with `payment_id` 1 apart and `created_at` <= 2 s apart, so genuine repeat payments are kept | Prevent | Mohamed Mosaad | Medium |
| 3 | Warn test on Bronze: number of new duplicate pairs per day (shows if the source bug grows) | Detect | Ahmed Nabil | Medium |
| 4 | Report the bug to the company (their payment system) | Prevent | Ahmed Nabil | Low |

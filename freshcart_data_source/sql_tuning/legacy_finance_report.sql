-- =============================================================================
-- finance_store_daily_report.sql
-- Owner: Finance (the analyst who wrote it left the company)    Status: "do not touch"
--
-- Store P&L per day for the last week, run every Monday by Finance DIRECTLY on the
-- production database (schema app). The week below is the one Finance escalated.
-- Complaint: "it takes minutes and the app becomes slow while it runs".
--
-- YOUR TASK: make it fast WITHOUT changing its results. See sql_tuning/README.md.
-- =============================================================================
SET TIME ZONE 'Africa/Cairo';

SELECT
    s.store_name,
    s.city,
    s.currency,
    d.report_day,

    -- delivered orders (internal test accounts excluded)
    (SELECT count(*)
       FROM app.orders o
      WHERE o.store_id = s.store_id
        AND to_char(o.placed_at, 'YYYY-MM-DD') = d.report_day
        AND o.order_status = 'delivered'
        AND o.customer_id NOT IN (SELECT c.customer_id FROM app.customers c
                                   WHERE lower(trim(c.email)) LIKE '%@test.freshcart.com')
    ) AS delivered_orders,

    -- value of the goods in those orders
    (SELECT coalesce(sum(oi.line_amount), 0)
       FROM app.order_items oi, app.orders o
      WHERE oi.order_id = o.order_id
        AND o.store_id = s.store_id
        AND to_char(o.placed_at, 'YYYY-MM-DD') = d.report_day
        AND o.order_status = 'delivered'
        AND o.customer_id NOT IN (SELECT c.customer_id FROM app.customers c
                                   WHERE lower(trim(c.email)) LIKE '%@test.freshcart.com')
    ) AS gross_sales,

    -- money received for those orders
    (SELECT coalesce(sum(p.amount), 0)
       FROM app.payments p
      WHERE p.payment_status = 'paid'
        AND p.order_id IN (SELECT o.order_id FROM app.orders o
                            WHERE o.store_id = s.store_id
                              AND to_char(o.placed_at, 'YYYY-MM-DD') = d.report_day
                              AND o.order_status = 'delivered'
                              AND o.customer_id NOT IN (SELECT c.customer_id FROM app.customers c
                                                         WHERE lower(trim(c.email)) LIKE '%@test.freshcart.com'))
    ) AS collected,

    -- refunds given on those orders
    (SELECT coalesce(sum(p.amount), 0)
       FROM app.payments p
      WHERE p.payment_status = 'refunded'
        AND p.order_id IN (SELECT o.order_id FROM app.orders o
                            WHERE o.store_id = s.store_id
                              AND to_char(o.placed_at, 'YYYY-MM-DD') = d.report_day
                              AND o.order_status = 'delivered'
                              AND o.customer_id NOT IN (SELECT c.customer_id FROM app.customers c
                                                         WHERE lower(trim(c.email)) LIKE '%@test.freshcart.com'))
    ) AS refunded

FROM (
    -- stores that had orders on each report day
    SELECT DISTINCT st.*, to_char(so.placed_at, 'YYYY-MM-DD') AS order_day
      FROM app.stores st
      JOIN app.orders so ON so.store_id = st.store_id
      JOIN app.order_items soi ON soi.order_id = so.order_id
) s
JOIN (SELECT to_char(day, 'YYYY-MM-DD') AS report_day
        FROM generate_series('2026-10-02'::date, '2026-10-08'::date, interval '1 day') AS day) d
  ON d.report_day = s.order_day
ORDER BY s.store_name, d.report_day;

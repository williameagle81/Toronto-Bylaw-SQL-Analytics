-- Analysis queries: Toronto ML&S Investigation Activity
-- Each query is separated by a line starting with "-- Q".

-- Q1: Monthly investigation volume, month-over-month change (LAG) and 3-month rolling average
WITH monthly AS (
    SELECT strftime('%Y-%m', in_date) AS month, COUNT(*) AS investigations
    FROM investigations
    WHERE in_date >= '2025-01-01' AND in_date < '2026-11-01'
    GROUP BY month
)
SELECT month,
       investigations,
       ROUND(100.0 * (investigations - LAG(investigations) OVER (ORDER BY month))
             / LAG(investigations) OVER (ORDER BY month), 1)                    AS mom_pct_change,
       ROUND(AVG(investigations) OVER (ORDER BY month
             ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0)                       AS rolling_3mo_avg
FROM monthly
ORDER BY month;

-- Q2: Category mix with share of total (window SUM) and share of Notice/Order escalations
SELECT category,
       COUNT(*)                                                    AS investigations,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)          AS pct_of_total,
       ROUND(100.0 * SUM(stage <> 'Initial') / COUNT(*), 1)        AS pct_notice_or_order
FROM investigations
GROUP BY category
ORDER BY investigations DESC;

-- Q3: Days from complaint to Notice/Order, by category (median and 90th percentile via ROW_NUMBER)
WITH gaps AS (
    SELECT category,
           CAST(julianday(notice_order_date) - julianday(in_date) AS INTEGER) AS days_to_notice
    FROM investigations
    WHERE notice_order_date IS NOT NULL AND in_date IS NOT NULL
      AND notice_order_date >= in_date
),
ranked AS (
    SELECT category, days_to_notice,
           ROW_NUMBER() OVER (PARTITION BY category ORDER BY days_to_notice) AS rn,
           COUNT(*)     OVER (PARTITION BY category)                         AS n
    FROM gaps
)
SELECT category,
       MAX(n)                                                               AS n,
       MIN(CASE WHEN rn >= 0.5 * n THEN days_to_notice END)                 AS median_days,
       MIN(CASE WHEN rn >= 0.9 * n THEN days_to_notice END)                 AS p90_days
FROM ranked
GROUP BY category
HAVING n >= 100
ORDER BY median_days DESC;

-- Q4: Properties with repeat investigations (top 10) using a ranked CTE
WITH per_property AS (
    SELECT p.property_key,
           COUNT(DISTINCT ip.investigation_id)             AS investigations,
           COUNT(DISTINCT i.category)                      AS distinct_categories,
           MIN(i.in_date)                                  AS first_seen,
           MAX(i.in_date)                                  AS last_seen
    FROM properties p
    JOIN investigation_properties ip USING (property_id)
    JOIN investigations i USING (investigation_id)
    WHERE p.is_placeholder = 0
    GROUP BY p.property_id
)
SELECT RANK() OVER (ORDER BY investigations DESC) AS rnk,
       property_key, investigations, distinct_categories, first_seen, last_seen
FROM per_property
ORDER BY investigations DESC
LIMIT 10;

-- Q5: How concentrated is repeat activity? Share of investigations at properties with 3+ cases
WITH per_property AS (
    SELECT ip.property_id, COUNT(DISTINCT ip.investigation_id) AS n
    FROM investigation_properties ip
    JOIN properties p USING (property_id)
    WHERE p.is_placeholder = 0
    GROUP BY ip.property_id
)
SELECT CASE WHEN n = 1 THEN '1 investigation'
            WHEN n = 2 THEN '2 investigations'
            WHEN n BETWEEN 3 AND 5 THEN '3-5 investigations'
            ELSE '6+ investigations' END                              AS property_group,
       COUNT(*)                                                       AS properties,
       SUM(n)                                                         AS investigations,
       ROUND(100.0 * SUM(n) / SUM(SUM(n)) OVER (), 1)                 AS pct_of_investigation_links
FROM per_property
GROUP BY property_group
ORDER BY MIN(n);

-- Q6: Active (not closed) backlog by age bucket and category
SELECT category,
       SUM(age_days <= 90)                      AS "0-90d",
       SUM(age_days BETWEEN 91 AND 365)         AS "91-365d",
       SUM(age_days > 365)                      AS "1y+",
       COUNT(*)                                 AS open_total
FROM v_open_backlog
GROUP BY category
HAVING open_total >= 50
ORDER BY open_total DESC;

-- Q7: Deficiencies per investigation by category (only investigations that have deficiency records)
WITH def_counts AS (
    SELECT investigation_id, COUNT(*) AS n_def,
           SUM(status = 'Open') AS n_open
    FROM deficiencies
    GROUP BY investigation_id
)
SELECT i.category,
       COUNT(*)                          AS investigations_with_deficiencies,
       ROUND(AVG(n_def), 2)              AS avg_deficiencies,
       MAX(n_def)                        AS max_deficiencies,
       ROUND(100.0 * SUM(n_open) / SUM(n_def), 1) AS pct_deficiencies_open
FROM def_counts dc
JOIN investigations i USING (investigation_id)
GROUP BY i.category
ORDER BY investigations_with_deficiencies DESC;

-- Q8: Most common deficiency locations, with share and rank (excluding blank locations)
SELECT location,
       COUNT(*)                                                   AS deficiencies,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)         AS pct,
       RANK() OVER (ORDER BY COUNT(*) DESC)                       AS rnk
FROM deficiencies
WHERE location IS NOT NULL
GROUP BY location
ORDER BY deficiencies DESC
LIMIT 10;

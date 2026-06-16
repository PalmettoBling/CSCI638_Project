-- 1) Additional B-tree index that pairs well with existing idx_activity_type for bitmap scans.
-- Example use in Adminer:
-- EXPLAIN ANALYZE
-- SELECT activity_id, activity_date, type, duration_minutes
-- FROM activity
-- WHERE type = 'run'
--   AND duration_minutes BETWEEN 30 AND 90;
--
-- PostgreSQL can combine idx_activity_type + idx_activity_duration_minutes
-- using BitmapAnd in a bitmap index scan plan.
CREATE INDEX IF NOT EXISTS idx_activity_duration_minutes ON activity(duration_minutes);


-- 2) Recursive query packaged as a function:
-- cumulative total distance by week (week-over-week).
CREATE OR REPLACE FUNCTION weekly_cumulative_distance()
RETURNS TABLE (
    week_start DATE,
    week_distance_km NUMERIC,
    cumulative_distance_km NUMERIC
) AS $$
WITH RECURSIVE weekly AS (
    SELECT
        date_trunc('week', activity_date)::date AS week_start,
        COALESCE(SUM(distance_km), 0)::numeric AS week_distance_km
    FROM activity
    GROUP BY 1
),
ordered AS (
    SELECT
        row_number() OVER (ORDER BY week_start) AS rn,
        week_start,
        week_distance_km
    FROM weekly
),
running AS (
    SELECT
        rn,
        week_start,
        week_distance_km,
        week_distance_km AS cumulative_distance_km
    FROM ordered
    WHERE rn = 1

    UNION ALL

    SELECT
        o.rn,
        o.week_start,
        o.week_distance_km,
        (r.cumulative_distance_km + o.week_distance_km)::numeric AS cumulative_distance_km
    FROM running r
    JOIN ordered o ON o.rn = r.rn + 1
)
SELECT
    week_start,
    week_distance_km,
    cumulative_distance_km
FROM running
ORDER BY week_start;
$$ LANGUAGE sql STABLE;


-- 3) MapReduce-style setup for this dataset.
-- Map: each row maps to a numeric distance value.
-- Reduce: custom aggregate sums mapped values.
DROP AGGREGATE IF EXISTS mapreduce_sum(NUMERIC);
DROP FUNCTION IF EXISTS reduce_sum_numeric(NUMERIC, NUMERIC);

CREATE OR REPLACE FUNCTION reduce_sum_numeric(state NUMERIC, mapped_value NUMERIC)
RETURNS NUMERIC AS $$
    SELECT COALESCE(state, 0) + COALESCE(mapped_value, 0);
$$ LANGUAGE sql IMMUTABLE;

CREATE AGGREGATE mapreduce_sum(NUMERIC) (
    SFUNC = reduce_sum_numeric,
    STYPE = NUMERIC,
    INITCOND = '0'
);

DROP FUNCTION IF EXISTS mapreduce_distance_by_type(DATE, DATE);

CREATE OR REPLACE FUNCTION mapreduce_distance_by_type(
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL
)
RETURNS TABLE (
    activity_kind TEXT,
    total_distance_km NUMERIC
) AS $$
WITH mapped AS (
    SELECT
        a.type::TEXT AS activity_kind,
        COALESCE(a.distance_km, 0)::numeric AS mapped_distance
    FROM activity a
    WHERE (p_start_date IS NULL OR a.activity_date >= p_start_date)
      AND (p_end_date IS NULL OR a.activity_date <= p_end_date)
)
SELECT
    m.activity_kind,
    mapreduce_sum(m.mapped_distance) AS total_distance_km
FROM mapped m
GROUP BY m.activity_kind
ORDER BY m.activity_kind;
$$ LANGUAGE sql STABLE;

-- Example calls in Adminer:
-- SELECT * FROM weekly_cumulative_distance();
-- SELECT * FROM mapreduce_distance_by_type();
-- SELECT * FROM mapreduce_distance_by_type('2026-01-01', '2026-12-31');

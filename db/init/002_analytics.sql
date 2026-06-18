CREATE INDEX IF NOT EXISTS idx_activity_duration_minutes ON activity(duration_minutes);

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
    activity_type TEXT,
    total_distance_km NUMERIC
) AS $$
WITH mapped AS (
    SELECT
        a.type::TEXT AS activity_type_label,
        COALESCE(a.distance_km, 0)::numeric AS mapped_distance
    FROM activity a
    WHERE (p_start_date IS NULL OR a.activity_date >= p_start_date)
      AND (p_end_date IS NULL OR a.activity_date <= p_end_date)
)
SELECT
    m.activity_type_label AS activity_type,
    mapreduce_sum(m.mapped_distance) AS total_distance_km
FROM mapped m
GROUP BY m.activity_type_label
ORDER BY m.activity_type_label;
$$ LANGUAGE sql STABLE;


-- Baselines

DROP FUNCTION IF EXISTS baseline_activity_filter(TEXT, INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION baseline_activity_filter(
    p_type TEXT,
    p_min_duration INTEGER,
    p_max_duration INTEGER
)
RETURNS TABLE (
    activity_id BIGINT,
    activity_date DATE,
    type activity_type,
    duration_minutes INTEGER
) AS $$
SELECT
    a.activity_id,
    a.activity_date,
    a.type,
    a.duration_minutes
FROM activity a
WHERE lower(a.type::TEXT) = lower(p_type)
  AND (a.duration_minutes + 0) BETWEEN p_min_duration AND p_max_duration
ORDER BY a.activity_date, a.activity_id;
$$ LANGUAGE sql STABLE;


-- 2) Baseline cumulative weekly distance function using a correlated subquery.
-- This is typically slower than a recursive running-total approach as data grows.
DROP FUNCTION IF EXISTS baseline_weekly_cumulative_distance();

CREATE OR REPLACE FUNCTION baseline_weekly_cumulative_distance()
RETURNS TABLE (
    week_start DATE,
    week_distance_km NUMERIC,
    cumulative_distance_km NUMERIC
) AS $$
WITH weekly AS (
    SELECT
        date_trunc('week', a.activity_date)::date AS week_start,
        COALESCE(SUM(a.distance_km), 0)::numeric AS week_distance_km
    FROM activity a
    GROUP BY 1
)
SELECT
    w1.week_start,
    w1.week_distance_km,
    (
        SELECT COALESCE(SUM(w2.week_distance_km), 0)::numeric
        FROM weekly w2
        WHERE w2.week_start <= w1.week_start
    ) AS cumulative_distance_km
FROM weekly w1
ORDER BY w1.week_start;
$$ LANGUAGE sql STABLE;


-- 3) Baseline distance-by-type function using repeated scalar subqueries
-- (one scan per type) instead of a single grouped aggregate pass.
DROP FUNCTION IF EXISTS baseline_distance_by_type(DATE, DATE);

CREATE OR REPLACE FUNCTION baseline_distance_by_type(
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL
)
RETURNS TABLE (
    activity_type TEXT,
    total_distance_km NUMERIC
) AS $$
WITH types AS (
    SELECT DISTINCT a.type::TEXT AS activity_type
    FROM activity a
)
SELECT
    t.activity_type,
    (
        SELECT COALESCE(SUM(a2.distance_km), 0)::numeric
        FROM activity a2
        WHERE a2.type::TEXT = t.activity_type
          AND (p_start_date IS NULL OR a2.activity_date >= p_start_date)
          AND (p_end_date IS NULL OR a2.activity_date <= p_end_date)
    ) AS total_distance_km
FROM types t
ORDER BY t.activity_type;
$$ LANGUAGE sql STABLE;

-- Calls to make in Adminer

-- SELECT * FROM weekly_cumulative_distance();
-- Recursive query packaged as a function:
-- cumulative total distance by week (week-over-week).

-- 3) MapReduce-style setup for this dataset.
-- Map: each row maps to a numeric distance value.
-- Reduce: custom aggregate sums mapped values.
-- SELECT * FROM mapreduce_distance_by_type();
-- SELECT * FROM mapreduce_distance_by_type('2026-01-01', '2026-12-31');

-- SELECT * FROM baseline_activity_filter('run', 30, 90);
-- SELECT * FROM baseline_weekly_cumulative_distance();
-- SELECT * FROM baseline_distance_by_type();
-- SELECT * FROM baseline_distance_by_type('2026-01-01', '2026-12-31');

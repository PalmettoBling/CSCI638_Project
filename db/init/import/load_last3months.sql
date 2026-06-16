\set ON_ERROR_STOP on

BEGIN;

CREATE TEMP TABLE stg_routes (
    routes_name TEXT,
    terrain TEXT,
    difficulty TEXT
);

\copy stg_routes FROM '/docker-entrypoint-initdb.d/import/routes_last3months.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO routes (routes_name, terrain, difficulty)
SELECT s.routes_name, NULLIF(s.terrain, ''), NULLIF(s.difficulty, '')
FROM stg_routes s
WHERE NULLIF(TRIM(s.routes_name), '') IS NOT NULL
ON CONFLICT (routes_name) DO NOTHING;

CREATE TEMP TABLE stg_activities (
    activity_date DATE,
    type TEXT,
    duration_minutes INTEGER,
    distance_km NUMERIC,
    heart_rate SMALLINT,
    calories INTEGER,
    cadence SMALLINT,
    weather_type TEXT,
    temperature_c NUMERIC,
    humidity_percent SMALLINT,
    source_activity_id TEXT,
    activity_name TEXT
);

\copy stg_activities FROM '/docker-entrypoint-initdb.d/import/activities_last3months.csv' WITH (FORMAT csv, HEADER true);

WITH to_load AS (
    SELECT s.*
    FROM stg_activities s
    WHERE NOT EXISTS (
        SELECT 1
        FROM activity a
        WHERE a.activity_date = s.activity_date
          AND a.type = s.type::activity_type
          AND a.duration_minutes = s.duration_minutes
          AND a.distance_km IS NOT DISTINCT FROM s.distance_km
    )
)
SELECT add_activity(
    p_date        => t.activity_date,
    p_type        => t.type::activity_type,
    p_duration    => t.duration_minutes,
    p_route       => NULL,
    p_distance    => t.distance_km,
    p_heart_rate  => t.heart_rate,
    p_calories    => t.calories,
    p_cadence     => t.cadence,
    p_weather     => CASE
                        WHEN NULLIF(TRIM(t.weather_type), '') IS NULL THEN NULL
                        ELSE t.weather_type::weather_type
                     END,
    p_temperature => t.temperature_c,
    p_humidity    => t.humidity_percent
)
FROM to_load t;

COMMIT;

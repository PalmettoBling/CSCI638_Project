CREATE TYPE activity_type AS ENUM ('run', 'bike', 'kayak');
CREATE TYPE weather_type AS ENUM ('sunny', 'cloudy', 'rainy', 'snowy', 'windy', 'stormy', 'foggy');

CREATE TABLE IF NOT EXISTS routes (
    route_id    BIGSERIAL PRIMARY KEY,
    routes_name TEXT NOT NULL UNIQUE,
    terrain     TEXT,
    difficulty  TEXT
);

CREATE TABLE IF NOT EXISTS activity (
    activity_id       BIGSERIAL PRIMARY KEY,
    activity_date     DATE          NOT NULL,
    routes_name       TEXT          REFERENCES routes(routes_name),
    type              activity_type NOT NULL,
    distance_km       NUMERIC(8, 2),
    duration_minutes  INTEGER       NOT NULL CHECK (duration_minutes > 0)
);

CREATE TABLE IF NOT EXISTS metrics (
    metrics_id  BIGSERIAL PRIMARY KEY,
    activity_id BIGINT   NOT NULL UNIQUE REFERENCES activity(activity_id) ON DELETE CASCADE,
    heart_rate  SMALLINT CHECK (heart_rate BETWEEN 30 AND 240),
    calories    INTEGER,
    cadence     SMALLINT
);

CREATE TABLE IF NOT EXISTS weather (
    weather_id       BIGSERIAL PRIMARY KEY,
    activity_id      BIGINT       NOT NULL UNIQUE REFERENCES activity(activity_id) ON DELETE CASCADE,
    type             weather_type NOT NULL,
    temperature_c    NUMERIC(5, 2),
    humidity_percent SMALLINT     CHECK (humidity_percent BETWEEN 0 AND 100)
);

CREATE INDEX IF NOT EXISTS idx_activity_date        ON activity(activity_date);
CREATE INDEX IF NOT EXISTS idx_activity_type        ON activity(type);
CREATE INDEX IF NOT EXISTS idx_activity_routes_name ON activity(routes_name);


CREATE OR REPLACE FUNCTION add_route(
    p_name       TEXT,
    p_terrain    TEXT,
    p_difficulty TEXT
) RETURNS TEXT AS $$
BEGIN
    INSERT INTO routes (routes_name, terrain, difficulty)
    VALUES (p_name, p_terrain, p_difficulty);
    RETURN 'Route "' || p_name || '" added!';
EXCEPTION WHEN unique_violation THEN
    RETURN 'Error: Route "' || p_name || '" already exists.';
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION add_activity(
    p_date        DATE,
    p_type        activity_type,
    p_duration    INTEGER,
    p_route       TEXT         DEFAULT NULL,
    p_distance    NUMERIC      DEFAULT NULL,
    p_heart_rate  SMALLINT     DEFAULT NULL,
    p_calories    INTEGER      DEFAULT NULL,
    p_cadence     SMALLINT     DEFAULT NULL,
    p_weather     weather_type DEFAULT NULL,
    p_temperature NUMERIC      DEFAULT NULL,
    p_humidity    SMALLINT     DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    v_id BIGINT;
BEGIN
    INSERT INTO activity (activity_date, routes_name, type, distance_km, duration_minutes)
    VALUES (p_date, p_route, p_type, p_distance, p_duration)
    RETURNING activity_id INTO v_id;

    IF p_heart_rate IS NOT NULL OR p_calories IS NOT NULL OR p_cadence IS NOT NULL THEN
        INSERT INTO metrics (activity_id, heart_rate, calories, cadence)
        VALUES (v_id, p_heart_rate, p_calories, p_cadence);
    END IF;

    IF p_weather IS NOT NULL THEN
        INSERT INTO weather (activity_id, type, temperature_c, humidity_percent)
        VALUES (v_id, p_weather, p_temperature, p_humidity);
    END IF;

    RETURN 'Activity #' || v_id || ' recorded!';
EXCEPTION WHEN foreign_key_violation THEN
    RETURN 'Error: Route "' || p_route || '" not found. Add the route first.';
END;
$$ LANGUAGE plpgsql;

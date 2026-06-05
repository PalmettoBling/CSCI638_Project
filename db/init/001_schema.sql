CREATE TYPE activity_type AS ENUM ('run', 'bike', 'kayak');
CREATE TYPE weather_type AS ENUM ('sunny', 'cloudy', 'rainy', 'snowy', 'windy', 'stormy', 'foggy');

CREATE TABLE IF NOT EXISTS activity (
    activity_id BIGSERIAL PRIMARY KEY,
    activity_date DATE NOT NULL,
    type activity_type NOT NULL,
    distance_km NUMERIC(8, 2)
    duration_minutes INTEGER NOT NULL CHECK (duration_minutes > 0)
);

CREATE TABLE IF NOT EXISTS metrics (
    metrics_id BIGSERIAL PRIMARY KEY,
    activity_id BIGINT NOT NULL UNIQUE REFERENCES activity(activity_id) ON DELETE CASCADE,
    heart_rate SMALLINT CHECK (heart_rate BETWEEN 30 AND 240),
    calories INTEGER
    cadence SMALLINT
);

CREATE TABLE IF NOT EXISTS weather (
    weather_id BIGSERIAL PRIMARY KEY,
    activity_id BIGINT NOT NULL UNIQUE REFERENCES activity(activity_id) ON DELETE CASCADE,
    type weather_type NOT NULL,
    temperature_c NUMERIC(5, 2),
    humidity_percent SMALLINT CHECK (humidity_percent BETWEEN 0 AND 100)
);

CREATE INDEX IF NOT EXISTS idx_activity_date ON activity(activity_date);
CREATE INDEX IF NOT EXISTS idx_activity_type ON activity(type);
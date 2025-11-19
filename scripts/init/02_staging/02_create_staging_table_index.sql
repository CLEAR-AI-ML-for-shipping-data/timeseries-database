CREATE TABLE IF NOT EXISTS stg.csv_data (
    position_id SERIAL NOT NULL,
    gps_timestamp timestamp without time zone NOT NULL,
    mmsi VARCHAR(20),
    latitude float,
    longitude float,
    nav_status character varying COLLATE pg_catalog."default" NOT NULL,
    speed_over_ground float,
    heading float,
    course_over_ground float,
    CONSTRAINT csv_data_pkey PRIMARY KEY (position_id)
) TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS ON stg.csv_data (position_id);

ALTER TABLE
    IF EXISTS stg.csv_data OWNER TO clear;

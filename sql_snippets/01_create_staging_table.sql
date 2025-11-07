CREATE SCHEMA IF NOT EXISTS stg
    AUTHORIZATION clear;

drop table if exists stg.csv_data;

CREATE TABLE IF NOT EXISTS stg.csv_data
(
    position_id SERIAL NOT NULL,
	gps_timestamp timestamp without time zone NOT NULL,
    mmsi VARCHAR(20),
	latitude float,
	longitude float,
    nav_status character varying COLLATE pg_catalog."default" NOT NULL,
    CONSTRAINT csv_data_pkey PRIMARY KEY (position_id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS stg.csv_data
    OWNER to clear;

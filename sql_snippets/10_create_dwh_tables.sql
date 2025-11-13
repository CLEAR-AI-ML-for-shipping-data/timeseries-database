CREATE schema IF NOT EXISTS dwh;

CREATE extension IF NOT EXISTS postgis;
CREATE extension if not exists timescaledb;

DROP TABLE IF EXISTS dwh.ships CASCADE;

CREATE TABLE dwh.ships (
    id SERIAL NOT NULL,
    mmsi VARCHAR(20) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE (mmsi)
);

DROP TABLE IF EXISTS dwh.nav_statuses CASCADE;

CREATE TABLE dwh.nav_statuses (
    id serial NOT NULL,
    nav_status varchar NOT NULL,
    PRIMARY KEY(id),
    UNIQUE (nav_status)
);

DROP TABLE IF EXISTS dwh.positions CASCADE;

CREATE TABLE dwh.positions (
    position_id SERIAL NOT NULL,
    gps_position geometry(POINT, 4326) NOT NULL,
    ship_id INTEGER,
    gps_timestamp TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    nav_status_id integer,
    speed_over_ground float,
    heading float,
    course_over_ground float,
    PRIMARY KEY (position_id),
    FOREIGN KEY(ship_id) REFERENCES dwh.ships (id),
    FOREIGN KEY(nav_status_id) REFERENCES dwh.nav_statuses (id)
);

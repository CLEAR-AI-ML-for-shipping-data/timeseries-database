CREATE TABLE IF NOT EXISTS dwh.ships (
    id SERIAL NOT NULL,
    mmsi VARCHAR(20) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE (mmsi)
);

CREATE TABLE IF NOT EXISTS dwh.nav_statuses (
    id serial NOT NULL,
    nav_status varchar NOT NULL,
    PRIMARY KEY(id),
    UNIQUE (nav_status)
);

CREATE TABLE dwh.positions (
    position_id SERIAL NOT NULL,
    gps_position geometry(POINT, 4326) NOT NULL,
    ship_id INTEGER,
    gps_timestamp TIMESTAMPTZ,
    nav_status_id integer,
    speed_over_ground float,
    heading float,
    course_over_ground float,
    FOREIGN KEY(ship_id) REFERENCES dwh.ships (id),
    FOREIGN KEY(nav_status_id) REFERENCES dwh.nav_statuses (id)
);

SELECT
    create_hypertable('dwh.positions', 'gps_timestamp', 'ship_id', 50);

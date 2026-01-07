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

CREATE TABLE IF NOT EXISTS dwh.positions (
    position_id SERIAL NOT NULL,
    gps_position geometry(POINT, 4326) NOT NULL,
    ship_id INTEGER,
    gps_timestamp TIMESTAMPTZ,
    nav_status_id integer,
    speed_over_ground float,
    heading float,
    course_over_ground float,
    load_date TIMESTAMP WITHOUT TIME ZONE,
    FOREIGN KEY(ship_id) REFERENCES dwh.ships (id),
    FOREIGN KEY(nav_status_id) REFERENCES dwh.nav_statuses (id)
) WITH (
    tsdb.hypertable,
    tsdb.create_default_indexes = FALSE,
    tsdb.chunk_interval = '1 day'
);

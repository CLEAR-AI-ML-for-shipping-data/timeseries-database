CREATE schema IF NOT EXISTS dwh;

DROP TABLE IF EXISTS dwh.ships CASCADE;

CREATE TABLE dwh.ships (
    id SERIAL NOT NULL,
    mmsi VARCHAR(20) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE (mmsi)
);

DROP TABLE IF EXISTS dwh.positions CASCADE;

CREATE TABLE dwh.positions (
    position_id SERIAL NOT NULL,
    gps_position geometry(POINT, 4326) NOT NULL,
    ship_id INTEGER,
    gps_timestamp TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    nav_status VARCHAR NOT NULL,
    PRIMARY KEY (position_id),
    FOREIGN KEY(ship_id) REFERENCES dwh.ships (id)
);

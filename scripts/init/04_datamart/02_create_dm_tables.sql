-- Split the trajectories into two tables
-- 1) with just the beginning and end of the trajectory
-- 2) a full linestring, so that we can add a geo-index

CREATE TABLE IF NOT EXISTS dm.trajectory_limits (
    id SERIAL NOT NULL,
    ship_id BIGINT,
    datetime_start TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    datetime_stop TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY (ship_id) REFERENCES dwh.ships
);


CREATE TABLE IF NOT EXISTS dm.exported_trajectories (
    trajectory_id integer,
    mmsi varchar(20),
    datetime_start TIMESTAMPTZ,
    datetime_stop TIMESTAMPTZ,
    coordinates geometry(LINESTRING, 4326),
    timestamps timestamptz [],
    speed_over_ground float [],
    course_over_ground float [],
    heading float [],
    FOREIGN KEY(trajectory_id) REFERENCES dm.trajectory_limits (id)
);

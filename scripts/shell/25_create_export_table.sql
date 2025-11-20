DROP TABLE IF EXISTS dm.exported_trajectories;

CREATE TABLE dm.exported_trajectories (
    trajectory_id integer,
    mmsi varchar(20),
    datetime_start timestamptz,
    datetime_stop timestamptz,
    coordinates geometry(LINESTRING, 4326),
    timestamps timestamptz [],
    speed_over_ground float [],
    course_over_ground float [],
    heading float []
);

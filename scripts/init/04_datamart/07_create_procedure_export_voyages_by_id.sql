CREATE
OR REPLACE PROCEDURE dm.export_finished_trajectories_by_id(start_id integer, stop_id integer) LANGUAGE plpgsql AS
$$
DECLARE
BEGIN
WITH unlined_trajectories AS (
    SELECT
        trajectory_id,
        mmsi,
        datetime_start,
        datetime_stop,
        array_agg(gps_position) AS coordinates,
        array_agg(gps_timestamp) AS timestamps,
        array_agg(speed_over_ground) AS speed_over_ground,
        array_agg(course_over_ground) AS course_over_ground,
        array_agg(heading) AS heading
    FROM
        (
            SELECT
                tl.id AS trajectory_id,
                ships.mmsi,
                tl.datetime_start,
                tl.datetime_stop,
                pos.gps_position,
                pos.gps_timestamp,
                pos.speed_over_ground,
                pos.course_over_ground,
                pos.heading
            FROM
                (
                    SELECT
                        *
                    FROM
                        dm.trajectory_limits AS dtl
                    WHERE
                        datetime_stop < timestamp 'infinity'
                        AND dtl.id BETWEEN start_id AND stop_id
                ) AS tl
                LEFT JOIN dwh.positions AS pos ON pos.gps_timestamp BETWEEN tl.datetime_start AND datetime_stop
                AND tl.ship_id = pos.ship_id
                LEFT JOIN dwh.ships AS ships ON tl.ship_id = ships.id
            ORDER BY
                tl.id,
                pos.gps_timestamp ASC
        )
    GROUP BY
        trajectory_id,
        mmsi,
        datetime_start,
        datetime_stop
)
INSERT INTO
    dm.exported_trajectories (
        trajectory_id,
        mmsi,
        datetime_start,
        datetime_stop,
        coordinates,
        timestamps,
        speed_over_ground,
        course_over_ground,
        heading
    )
SELECT
    trajectory_id,
    mmsi,
    datetime_start,
    datetime_stop,
    ST_MakeLine(coordinates) AS coordinates,
    timestamps,
    speed_over_ground,
    course_over_ground,
    heading
FROM
    unlined_trajectories
    -- dm.trajectory_limits AS tl
    -- LEFT JOIN dwh.positions AS pos ON tl.ship_id = pos.ship_id
    -- AND pos.gps_timestamp BETWEEN tl.datetime_start AND tl.datetime_stop
    -- LEFT JOIN dwh.ships AS ships ON tl.ship_id = ships.id
    -- WHERE
    -- date(tl.datetime_start) = date_start
    -- tl.ship_id BETWEEN proc_min_ship_id
    -- AND proc_max_ship_id;
;

END;

$$
;

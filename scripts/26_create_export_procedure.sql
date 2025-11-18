DROP PROCEDURE IF EXISTS dm.export_trajectories;

CREATE
OR REPLACE PROCEDURE dm.export_trajectories(proc_ship_id integer) language plpgsql AS
$$
DECLARE
BEGIN
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
    DISTINCT ON (tl.id) tl.id AS trajectory_id,
    ships.mmsi,
    tl.datetime_start,
    tl.datetime_stop,
    ST_MakeLine(
        array_agg(gps_position) over (
            PARTITION by tl.id
            ORDER BY
                gps_timestamp ROWS BETWEEN unbounded preceding
                AND unbounded following
        )
    ) AS coordinates,
    array_agg(gps_timestamp) over (
        PARTITION by tl.id
        ORDER BY
            gps_timestamp ROWS BETWEEN unbounded preceding
            AND unbounded following
    ) AS timestamps,
    array_agg(speed_over_ground) over (
        PARTITION by tl.id
        ORDER BY
            gps_timestamp ROWS BETWEEN unbounded preceding
            AND unbounded following
    ) AS speed_over_ground,
    array_agg(course_over_ground) over (
        PARTITION by tl.id
        ORDER BY
            gps_timestamp ROWS BETWEEN unbounded preceding
            AND unbounded following
    ) AS course_over_ground,
    array_agg(heading) over (
        PARTITION by tl.id
        ORDER BY
            gps_timestamp ROWS BETWEEN unbounded preceding
            AND unbounded following
    ) AS heading
FROM
    dm.trajectory_limits AS tl
    LEFT JOIN dwh.positions AS pos ON tl.ship_id = pos.ship_id
    AND pos.gps_timestamp BETWEEN tl.datetime_start
    AND tl.datetime_stop
    LEFT JOIN dwh.ships AS ships ON tl.ship_id = ships.id
WHERE
    tl.ship_id = proc_ship_id;

END;

$$;

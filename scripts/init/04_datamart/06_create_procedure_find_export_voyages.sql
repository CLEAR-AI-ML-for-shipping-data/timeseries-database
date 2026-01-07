CREATE
OR REPLACE PROCEDURE dm.find_export_voyages(
    proc_ship_id_min integer,
    proc_ship_id_max integer
) LANGUAGE plpgsql AS
$$
DECLARE
BEGIN
-- Remove an open-ended voyage
DELETE FROM
    dm.trajectory_limits
WHERE
    ship_id BETWEEN proc_ship_id_min AND proc_ship_id_max
    AND datetime_stop = TIMESTAMP 'infinity';

CREATE TEMP TABLE tmp_ship_positions AS (
    WITH ship_timelimits AS (
        SELECT
            ships.id AS ship_id,
            max(tl.datetime_stop) AS max_datetime_stop
        FROM
            dwh.ships AS ships
            LEFT JOIN dm.trajectory_limits AS tl ON ships.id = tl.ship_id
        WHERE
            ships.id BETWEEN proc_ship_id_min AND proc_ship_id_max
        GROUP BY
            ships.id
    )
    SELECT
        pos.*
    FROM
        ship_timelimits AS stl
        INNER JOIN dwh.positions AS pos ON stl.ship_id = pos.ship_id
        AND (
            stl.max_datetime_stop < pos.gps_timestamp
            OR stl.max_datetime_stop IS NULL
        )
);

CREATE TEMP TABLE tmp_deltas AS (
    SELECT
        ship_id,
        gps_position,
        gps_timestamp,
        nav_status,
        gps_timestamp - lag(gps_timestamp) OVER(
            PARTITION BY ship_id
            ORDER BY
                gps_timestamp ROWS BETWEEN 1 preceding AND CURRENT ROW
        ) AS delta_t,
        lag(nav_status) OVER(
            PARTITION BY ship_id
            ORDER BY
                gps_timestamp ROWS BETWEEN 1 preceding AND CURRENT ROW
        ) AS nav_status_prev
    FROM
        tmp_ship_positions AS pos
        LEFT JOIN dwh.nav_statuses AS nav ON pos.nav_status_id = nav.id
);

-- Determine engine transitions and timegaps
CREATE TEMP TABLE tmp_transitions AS (
    SELECT
        d.*,
        CASE
            WHEN d.nav_status_prev != 'Engine'
            AND d.nav_status = 'Engine' THEN 1
            ELSE 0
        END AS start_engine,
        CASE
            WHEN d.nav_status_prev = 'Engine'
            AND d.nav_status != 'Engine' THEN 1
            ELSE 0
        END AS stop_engine,
        CASE
            WHEN delta_t > '15 min 0 sec'
            AND d.nav_status_prev = 'Engine'
            AND d.nav_status = 'Engine' THEN 1
            ELSE 0
        END AS start_after_gap
    FROM
        tmp_deltas AS d
);

-- Combine the starts and stops
CREATE TEMP TABLE tmp_trajectory_transitions AS (
    SELECT
        m.*
    FROM
        (
            SELECT
                tt.ship_id,
                tt.gps_position,
                tt.gps_timestamp,
                tt.nav_status,
                greatest(start_engine, start_after_gap) AS start_trajectory,
                greatest(
                    stop_engine -- The stop before a gap
,
                    lead(start_after_gap) OVER (
                        PARTITION BY ship_id
                        ORDER BY
                            gps_timestamp ROWS BETWEEN CURRENT ROW
                            AND 1 following
                    )
                ) AS stop_trajectory
            FROM
                tmp_transitions AS tt
        ) AS m
    WHERE
        m.start_trajectory = 1
        OR m.stop_trajectory = 1
);

-- Remove the first datapoint of a ship if it is a stop point
CREATE TEMP TABLE tmp_numbered_transitions AS (
    SELECT
        tt.*,
        row_number() OVER(
            PARTITION BY ship_id
            ORDER BY
                gps_timestamp
        ) AS regular_rank
    FROM
        tmp_trajectory_transitions AS tt
);

DELETE FROM
    tmp_numbered_transitions
WHERE
    stop_trajectory = 1
    AND regular_rank = 1;

ALTER TABLE
    tmp_numbered_transitions DROP COLUMN regular_rank;

-- We do not deal with voyages that have no final stop condition
-- We just set the stop datetime to 9999-12-31 00:00:00
CREATE TEMP TABLE tmp_trajectory_boundaries AS (
    SELECT
        t1.ship_id,
        t1.gps_timestamp AS timestamp_start
        -- Select closest stop to start
        -- If the trajectory is open, set the stop datetime to infinity
,
        coalesce(min(t2.gps_timestamp), timestamp 'infinity') AS timestamp_stop
        -- A table with all the trajectory starts
    FROM
        (
            SELECT
                *
            FROM
                tmp_numbered_transitions
            WHERE
                start_trajectory = 1
        ) AS t1
        -- A table with all the trajectory stops
        LEFT JOIN (
            SELECT
                *
            FROM
                tmp_numbered_transitions
            WHERE
                stop_trajectory = 1
        ) AS t2 ON t1.ship_id = t2.ship_id
        -- Do the less-or-equal comparison for points with both stop and start
        AND t1.gps_timestamp <= t2.gps_timestamp
    GROUP BY
        t1.ship_id,
        t1.gps_timestamp
    ORDER BY
        t1.ship_id,
        t1.gps_timestamp
);

INSERT INTO
    dm.trajectory_limits (ship_id, datetime_start, datetime_stop)
SELECT
    ship_id,
    timestamp_start,
    timestamp_stop
FROM
    tmp_trajectory_boundaries;

-- Export the actual trajectories to a different table
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
    DISTINCT ON (tr.id) tr.id AS trajectory_id,
    ships.mmsi,
    tl.timestamp_start,
    tl.timestamp_stop,
    ST_MakeLine(
        array_agg(gps_position) OVER (
            PARTITION by tr.id
            ORDER BY
                gps_timestamp ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        )
    ) AS coordinates,
    array_agg(gps_timestamp) OVER (
        PARTITION by tr.id
        ORDER BY
            gps_timestamp ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS timestamps,
    array_agg(speed_over_ground) OVER (
        PARTITION by tr.id
        ORDER BY
            gps_timestamp ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS speed_over_ground,
    array_agg(course_over_ground) OVER (
        PARTITION by tr.id
        ORDER BY
            gps_timestamp ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS course_over_ground,
    array_agg(heading) OVER (
        PARTITION by tr.id
        ORDER BY
            gps_timestamp ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS heading
FROM
    tmp_trajectory_boundaries AS tl
    LEFT JOIN tmp_ship_positions AS pos ON tl.ship_id = pos.ship_id
    AND pos.gps_timestamp BETWEEN tl.timestamp_start AND tl.timestamp_stop
    LEFT JOIN dwh.ships AS ships ON tl.ship_id = ships.id
    LEFT JOIN dm.trajectory_limits AS tr ON tr.ship_id = tl.ship_id
    AND tr.datetime_start = tl.timestamp_start
    AND tr.datetime_stop = tl.timestamp_stop;

END;

$$
;

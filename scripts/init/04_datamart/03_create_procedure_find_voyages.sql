CREATE
OR REPLACE PROCEDURE dm.find_voyages(proc_ship_id integer) LANGUAGE plpgsql AS
$$
DECLARE
BEGIN
-- Remove an open-ended voyage
DELETE FROM
    dm.trajectory_limits
WHERE
    ship_id = proc_ship_id
    AND datetime_stop = TIMESTAMP 'infinity';

CREATE TEMP TABLE tmp_ship_positions AS (
    SELECT
        *
    FROM
        dwh.positions AS pos
    WHERE
        pos.ship_id = proc_ship_id
        AND pos.gps_timestamp > (
            SELECT
                coalesce(max(datetime_stop), TIMESTAMP '-infinity')
            FROM
                dm.trajectory_limits
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

END;

$$
;

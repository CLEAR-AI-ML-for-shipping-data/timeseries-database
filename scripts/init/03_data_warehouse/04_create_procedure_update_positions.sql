CREATE
OR REPLACE PROCEDURE dwh.insert_into_dwh (min_id integer, max_id integer) LANGUAGE PLPGSQL AS
$$
DECLARE
BEGIN
/* This process consists of several steps
 1) select a chunk from the staging table
 2) fetch the correct ship_id and nav_status_id
 3) Insert the normalized rows into the positions table
 */
WITH tmp_stg_csv_data AS (
    SELECT
        *
    FROM
        stg.csv_data
    WHERE
        position_id BETWEEN min_id AND max_id
)
INSERT INTO
    dwh.positions (
        gps_position,
        ship_id,
        gps_timestamp,
        nav_status_id,
        speed_over_ground,
        heading,
        course_over_ground,
        load_date
    )
SELECT
    ST_Point(t1.longitude, t1.latitude, 4326) AS gps_position,
    ships.id AS ship_id,
    t1.gps_timestamp,
    nav.id AS nav_status_id,
    t1.speed_over_ground,
    t1.heading,
    t1.course_over_ground,
    t1.load_date
FROM
    tmp_stg_csv_data AS t1
    LEFT JOIN dwh.ships AS ships ON t1.mmsi = ships.mmsi
    LEFT JOIN dwh.nav_statuses AS nav ON t1.nav_status = nav.nav_status;

END;

$$
;

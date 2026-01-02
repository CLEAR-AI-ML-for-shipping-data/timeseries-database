CREATE
OR REPLACE PROCEDURE dwh.update_ships_statuses () LANGUAGE PLPGSQL AS
$$
DECLARE
BEGIN
-- Select rows not yet inserted into the dwh
CREATE TEMP TABLE tmp_new_rows AS
SELECT
    mmsi,
    nav_status
FROM
    stg.csv_data AS t1
WHERE
    t1.load_date > (
        SELECT
            coalesce(MAX(load_date), timestamp '-infinity')
        FROM
            dwh.positions
    );

-- Update the ships table
INSERT INTO
    dwh.ships (mmsi)
SELECT
    mmsi
FROM
    (
        SELECT
            t1.mmsi,
            ships.id
        FROM
            (
                SELECT
                    mmsi
                FROM
                    tmp_new_rows
                GROUP BY
                    mmsi
            ) AS t1
            LEFT JOIN dwh.ships ON t1.mmsi = ships.mmsi
        WHERE
            ships.id IS NULL
    );

-- Update the nav_status table
INSERT INTO
    dwh.nav_statuses(nav_status)
SELECT
    nav_status
FROM
    (
        SELECT
            t1.nav_status,
            nav.id
        FROM
            (
                SELECT
                    nav_status
                FROM
                    tmp_new_rows
                GROUP BY
                    nav_status
            ) AS t1
            LEFT JOIN dwh.nav_statuses AS nav ON t1.nav_status = nav.nav_status
        WHERE
            nav.id IS NULL
    );

END;

$$
;

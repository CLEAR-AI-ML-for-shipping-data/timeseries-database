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
                    DISTINCT mmsi
                FROM
                    stg.csv_data
            ) AS t1
            LEFT JOIN dwh.ships ON t1.mmsi = ships.mmsi
        WHERE
            ships.id IS NULL
    );

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
                    DISTINCT nav_status
                FROM
                    stg.csv_data
            ) AS t1
            LEFT JOIN dwh.nav_statuses AS nav ON t1.nav_status = nav.nav_status
        WHERE
            nav.id IS NULL
    );

INSERT INTO
    dwh.positions (
        gps_position,
        ship_id,
        gps_timestamp,
        nav_status_id,
    )
SELECT
    *
FROM
    (
        SELECT
            ST_Point(t1.longitude, t1.latitude, 4326) AS gps_position,
            ships.id AS ship_id,
            t1.gps_timestamp,
            nav.id AS nav_status_id,
        FROM
            stg.csv_data AS t1
            LEFT JOIN dwh.ships AS ships ON t1.mmsi = ships.mmsi
            LEFT JOIN dwh.nav_statuses AS nav ON t1.nav_status = nav.nav_status
    )

from argparse import ArgumentParser
from multiprocessing import Pool
from typing import Tuple

import psycopg
from loguru import logger
from tqdm import tqdm

INDEX_NAME = "positions_gps_timestamp_ship_id_idx"


def get_number_of_rows_for_update(dbname: str):
    """Find the number of rows to update in the DWH.

    Args:
        dbname: database connection string

    Returns:
        the number of rows in the staging table
    """
    conn = psycopg.connect(dbname)
    with conn:
        res = conn.execute("SELECT COUNT(*) FROM stg.csv_data")
        row_1 = res.fetchone()
        return row_1[0]


def get_min_max_rownumber_for_update(dbname: str):
    """Get the range of rownumbers which need to be inserted into the DWH

    Args:
        dbname: database connection strings

    Returns:
        the minimum and maximum row number
    """
    select_stmt = (
        "SELECT MIN(position_id), MAX(position_id) FROM stg.csv_data WHERE load_date >"
        " (SELECT COALESCE(MAX(load_date), TIMESTAMP '-infinity') FROM dwh.positions);"
    )
    with psycopg.connect(dbname) as conn:
        res = conn.execute(select_stmt)
        row_1 = res.fetchone()
        if row_1 is None:
            logger.error("Rownumber query did not return any rows!")
            raise SystemExit
        return row_1


def call_ships_nav_statuses_procedure(dbname: str):
    """Call the update procedure for ships and navigational statuses.

    This will insert ships and nav statuses from new rows in stg.csv_data into
    their respective tables.

    Args:
        dbname: database connection string
    """
    sql_stmt = "CALL dwh.update_ships_statuses();"
    with psycopg.connect(dbname) as conn:
        conn.execute(sql_stmt)


def call_procedure(index_min: int, index_max: int, dbname: str):
    """Call the update procedure for range of rows.

    This will add this range of rows to the DWH tables.
    Note that index_min and index_max are inclusive, per the PostGRES BETWEEN keyword

    Args:
        index_min: starting row
        index_max: ending row
        dbname: database connection string
    """
    sql_stmt = f"CALL dwh.insert_into_dwh( {index_min}, {index_max} );"
    with psycopg.connect(dbname) as conn:
        # _ = conn.execute(sql_stmt)
        conn.execute(sql_stmt)


def star_call_procedure(args: Tuple):
    """See call_procedure.

    This function exists purely for parallel processing.

    Args:
        args: arguments to be passed to call_procedure
    """
    call_procedure(*args)


def create_index(dbname: str):
    """Build an index for the dwh.positions table

    Args:
        dbname: database connection string
    """
    sql_stmt = (
        f"CREATE INDEX {INDEX_NAME} ON dwh.positions (gps_timestamp ASC, ship_id);"
    )
    with psycopg.connect(dbname) as conn:
        logger.info(f"Building index {INDEX_NAME}, this might take a while...")
        conn.execute(sql_stmt)


def drop_index(dbname: str):
    """Drop the index for the dwh.positions table

    Args:
        dbname: database connection string
    """
    sql_stmt = f"DROP INDEX IF EXISTS dwh.{INDEX_NAME};"
    with psycopg.connect(dbname) as conn:
        logger.info(f"Dropping index {INDEX_NAME}")
        conn.execute(sql_stmt)


if __name__ == "__main__":
    parser = ArgumentParser(prog="Add CSV data")

    parser.add_argument(
        "-d", "--dbname", type=str, required=True, help="database connection string"
    )
    parser.add_argument(
        "-b",
        "--batchsize",
        type=int,
        default=1_000_000,
        help="rows to be added per batch",
    )
    parser.add_argument("-n", "--nworkers", type=int, default=4)

    args = parser.parse_args()
    dbname = args.dbname
    batchsize = args.batchsize
    nworkers = args.nworkers

    # Update the ship and nav_status tables
    logger.info("Updating ships and nav statuses")
    call_ships_nav_statuses_procedure(dbname)
    # Get the first and last row_id to be inserted
    first_row_id, last_row_id = get_min_max_rownumber_for_update(dbname)
    if first_row_id is None and last_row_id is None:
        logger.warning("No new rows found in staging table")
        raise SystemExit

    logger.info(f"Inserting rows {first_row_id} through {last_row_id} into DWH")

    # Insert the new rows into the dwh in a parallel manner
    drop_index(dbname)

    input_args = []
    for i in range(first_row_id, last_row_id + 1, batchsize):
        input_args.append((i, i + batchsize - 1, dbname))
    logger.info(f"Starting batch insertion, with batch size {batchsize}")
    with Pool(nworkers) as p:
        result = list(
            tqdm(p.imap(star_call_procedure, input_args), total=len(input_args))
        )

    create_index(dbname)

from argparse import ArgumentParser
from typing import Tuple

import psycopg
from loguru import logger
from tqdm import trange

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

    nrows = get_number_of_rows_for_update(dbname)
    logger.info(f"Found {nrows} rows to be inserted")
    drop_index(dbname=dbname)

    logger.info(f"Starting batch insertion, with batch size {batchsize}")
    for i in trange(1, nrows + 1, batchsize, dynamic_ncols=True):
        call_procedure(i, i + batchsize - 1, dbname)

    create_index(dbname=dbname)

    # # Maybe this parallel process can be used if we redesign the update procedure
    # input_args = []
    # for i in trange(1, nrows + 1, batchsize):
    #     input_args.append((i, i + batchsize - 1, dbname))
    # with Pool(nworkers) as p:
    #     result = list(
    #         tqdm(p.imap(star_call_procedure, input_args), total=len(input_args))
    #     )

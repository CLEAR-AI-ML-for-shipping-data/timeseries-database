from argparse import ArgumentParser
from itertools import repeat
from multiprocessing import Pool
from typing import List

import psycopg
from loguru import logger
from tqdm import tqdm

INDEX_NAME = "trajectory_limits_datetime_start_ship_id_idx"


def get_ships_for_update(dbname: str):
    conn = psycopg.connect(dbname)
    with conn:
        res = conn.execute("SELECT id FROM dwh.ships ")
        rows = res.fetchall()
        return [i[0] for i in rows]


def create_index(dbname: str):
    sql_stmt = (
        f"CREATE INDEX IF NOT EXISTS {INDEX_NAME} ON dm.trajectory_limits "
        "(datetime_start ASC, ship_id);"
    )
    with psycopg.connect(dbname) as conn:
        logger.info(f"Building index {INDEX_NAME}, this might take a while...")
        conn.execute(sql_stmt)


def drop_index(dbname: str):
    sql_stmt = f"DROP INDEX IF EXISTS dm.{INDEX_NAME};"
    with psycopg.connect(dbname) as conn:
        logger.info(f"Dropping index {INDEX_NAME}")
        conn.execute(sql_stmt)


def find_voyages_per_ship(dbname: str, ship_id: int):
    sql_stmt = f"CALL dm.find_voyages( {ship_id} );"
    with psycopg.connect(dbname) as conn:
        conn.execute(sql_stmt)


def star_find_voyages(input_args):
    return find_voyages_per_ship(*input_args)


if __name__ == "__main__":
    parser = ArgumentParser(prog="Add CSV data")

    parser.add_argument("-d", "--dbname", type=str, required=True)
    parser.add_argument("-b", "--batchsize", type=int, default=1_000_000)
    parser.add_argument("-n", "--nworkers", type=int, default=4)

    args = parser.parse_args()
    dbname = args.dbname
    batchsize = args.batchsize
    nworkers = args.nworkers

    ship_ids: List[int] = get_ships_for_update(dbname)
    logger.info(f"Found {len(ship_ids)} ships to find trajectories for")
    drop_index(dbname=dbname)

    input_args = list(zip(repeat(dbname), ship_ids))

    with Pool(nworkers) as p:
        result = list(
            tqdm(
                p.imap(star_find_voyages, input_args),
                total=len(input_args),
                unit="ship",
            )
        )

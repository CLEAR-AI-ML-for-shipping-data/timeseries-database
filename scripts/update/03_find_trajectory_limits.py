from argparse import ArgumentParser
from multiprocessing import Pool
from typing import List, Tuple

import psycopg
from loguru import logger
from tqdm import tqdm

INDEX_NAME = "trajectory_limits_datetime_start_ship_id_idx"


def get_ships_for_update(dbname: str):
    """Retrieve all the ship ids.

    Args:
        dbname: database connection string

    Returns:
        a list of ship IDs
    """
    conn = psycopg.connect(dbname)
    with conn:
        res = conn.execute("SELECT id FROM dwh.ships ")
        rows = res.fetchall()
        return [i[0] for i in rows]


def create_index(dbname: str):
    """Create index for trajectory limits table, based on ship id and start time.

    Args:
        dbname: database connection string
    """
    sql_stmt = (
        f"CREATE INDEX IF NOT EXISTS {INDEX_NAME} ON dm.trajectory_limits "
        "(datetime_start ASC, ship_id);"
    )
    with psycopg.connect(dbname) as conn:
        logger.info(f"Building index {INDEX_NAME}, this might take a while...")
        conn.execute(sql_stmt)


def drop_index(dbname: str):
    """Drop index for trajectory limits table.

    Args:
        dbname: database connection string
    """
    sql_stmt = f"DROP INDEX IF EXISTS dm.{INDEX_NAME};"
    with psycopg.connect(dbname) as conn:
        logger.info(f"Dropping index {INDEX_NAME}")
        conn.execute(sql_stmt)


def find_voyages_per_ship(dbname: str, ship_id_min: int, ship_id_max: int):
    """Call the find_voyages stored procedure for a ship.

    Args:
        dbname: database connection string
        ship_id: id of the ship
    """
    sql_stmt = f"CALL dm.find_voyages( {ship_id_min}, {ship_id_max} );"
    with psycopg.connect(dbname) as conn:
        conn.execute(sql_stmt)


def star_find_voyages(input_args: Tuple):
    """Wrapper around find_voyages_per_ship for parallel processing.

    Args:
        input_args: arguments to find_voyages_per_ship
    """
    return find_voyages_per_ship(*input_args)


def export_voyages_per_ship(dbname: str, ship_id: int):
    """Call the procedure for exporting voyage trajectories.

    This depends on the endpoints of the voyage having been previously found with
    the find_voyages_per_ship function. The exporting voyages entails creating a
    LineString geometry that is stored in a different table.

    Args:
        dbname: database connection string
        ship_id: ID of the ship.
    """
    sql_stmt = f"CALL dm.export_trajectories( {ship_id} );"
    with psycopg.connect(dbname) as conn:
        conn.execute(sql_stmt)


def star_export_voyages(input_args: Tuple):
    """Wrapper around export_voyages_per_ship for parallel processing.

    Args:
        input_args: arguments to export_voyages_per_ship
    """
    return export_voyages_per_ship(*input_args)


if __name__ == "__main__":
    parser = ArgumentParser(prog="Add CSV data")

    parser.add_argument("-d", "--dbname", type=str, required=True)
    parser.add_argument("-b", "--batchsize", type=int, default=1_000)
    parser.add_argument("-n", "--nworkers", type=int, default=4)
    parser.add_argument("-s", "--skip_finding", action="store_true")
    parser.add_argument("-x", "--export", action="store_true")

    args = parser.parse_args()
    dbname = args.dbname
    batchsize = args.batchsize
    nworkers = args.nworkers
    skip_finding = args.skip_finding
    export = args.export

    ship_ids: List[int] = get_ships_for_update(dbname)

    total_ships = len(ship_ids)
    input_args = []

    for i in range(0, total_ships + 1, batchsize):
        input_args.append((dbname, i, i + batchsize - 1))

    if skip_finding is False:
        logger.info(f"Found {len(ship_ids)} ships to find trajectories for")
        drop_index(dbname=dbname)
        logger.info(
            f"Finding new voyages for {len(ship_ids)} ships, in batches of {batchsize}"
        )
        with Pool(nworkers) as p:
            result = list(
                tqdm(
                    p.imap(star_find_voyages, input_args),
                    total=len(input_args),
                    # unit="ship",
                    unit="batch",
                    dynamic_ncols=True,
                )
            )
        create_index(dbname=dbname)

    if export is True:
        logger.info(f"Exporting voyages for {len(ship_ids)} ships")
        with Pool(nworkers) as p:
            result = list(
                tqdm(
                    p.imap(star_export_voyages, input_args),
                    total=len(input_args),
                    unit="ship",
                    dynamic_ncols=True,
                )
            )

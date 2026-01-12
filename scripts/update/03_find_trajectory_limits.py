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


def get_trajectories_for_export(dbname: str):
    query = (
        "select id from dm.trajectory_limits as tl left join dm.exported_trajectories"
        " as et on tl.id = et.trajectory_id where et.trajectory_id is null "
        "and tl.datetime_stop - tl.datetime_start > interval '12 hours'"
        "and tl.datetime_stop < timestamp 'infinity';"
    )
    with psycopg.connect(dbname) as conn:
        res = conn.execute(query=query)
        rows = res.fetchall()
        return [row[0] for row in rows]


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


def find_export_voyages_per_ship(dbname: str, ship_id_min: int, ship_id_max: int):
    """Call the find_export_voyages stored procedure for a ship.

    Args:
        dbname: database connection string
        ship_id: id of the ship
    """
    sql_stmt = f"CALL dm.find_export_voyages( {ship_id_min}, {ship_id_max} );"
    with psycopg.connect(dbname) as conn:
        conn.execute(sql_stmt)


def star_find_export_voyages(input_args: Tuple):
    """Wrapper around find_export_voyages_per_ship for parallel processing.

    Args:
        input_args: arguments to find_voyages_per_ship
    """
    return find_export_voyages_per_ship(*input_args)


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


def batch_export_voyages(dbname: str, min_ship_id: int, max_ship_id: int):
    """Call the procedure for exporting voyage trajectories.

    This depends on the endpoints of the voyage having been previously found with
    the find_voyages_per_ship function. The exporting voyages entails creating a
    LineString geometry that is stored in a different table.

    Args:
        dbname: database connection string
        ship_id: ID of the ship.
    """
    sql_stmt = f"CALL dm.batch_export_trajectories( {min_ship_id}, {max_ship_id} );"
    with psycopg.connect(dbname) as conn:
        conn.execute(sql_stmt)


def star_batch_export_voyages(input_args: Tuple):
    """Wrapper around batch_export_voyages for parallel processing.

    Args:
        input_args: arguments to batch_export_voyages
    """
    return batch_export_voyages(*input_args)


def star_run_query(input_args: Tuple):
    dbname, query = input_args
    with psycopg.connect(dbname) as conn:
        conn.execute(query)


if __name__ == "__main__":
    parser = ArgumentParser(prog="Add CSV data")

    parser.add_argument("-d", "--dbname", type=str, required=True)
    parser.add_argument("-b", "--batchsize", type=int, default=1_000)
    # Disable the multiple workers option for now
    # Parallel processing somehow leads to inconsistent results
    # parser.add_argument("-n", "--nworkers", type=int, default=4)
    parser.add_argument("-s", "--skip_finding", action="store_true")
    parser.add_argument("-x", "--export", action="store_true")

    args = parser.parse_args()
    dbname = args.dbname
    batchsize = args.batchsize
    # nworkers = args.nworkers
    nworkers = 1
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
        star_func = star_find_voyages
        log_message = (
            f"Finding new voyages for {len(ship_ids)} ships, in batches of {batchsize}"
        )
        logger.info(log_message)
        with Pool(nworkers) as p:
            result = list(
                tqdm(
                    p.imap(star_func, input_args),
                    total=len(input_args),
                    unit="batch",
                    dynamic_ncols=True,
                )
            )
        create_index(dbname=dbname)

    if export is True:
        trajectory_ids = get_trajectories_for_export(dbname=dbname)
        query_strings = []
        input_args = []
        batchsize = 10

        for i in range(0, len(trajectory_ids) + 1, batchsize):
            trajs = ",".join(
                [
                    str(i)
                    for i in trajectory_ids[i : min(i + batchsize, len(trajectory_ids))]
                ]
            )
            input_args.append(
                (dbname, f"call dm.export_multiple_trajectory_by_id( ARRAY[{trajs}] );")
            )

        logger.info(
            f"Exporting {len(trajectory_ids)} voyages in batches of {batchsize}..."
        )
        with Pool(nworkers) as p:
            result = list(
                tqdm(
                    p.imap(star_run_query, input_args),
                    total=len(input_args),
                    unit="batch",
                    dynamic_ncols=True,
                )
            )

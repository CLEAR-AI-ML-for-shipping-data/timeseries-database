import inspect
import os
from argparse import ArgumentParser
from pathlib import Path
from typing import Optional

import psycopg
from loguru import logger

# We skip this file, because it assumes the database to not exist
# This would require connecting to a different database, e.g. postgresql
# to create this database, then connect to the new database, and run the scripts
SKIP_FILE = "01_create_database.sql"


def apply_source_file(dbname: str, sourcefile: Path):
    with open(sourcefile) as file:
        lines = file.readlines()

    sql_stmt = " ".join(lines)
    last_3_layers = "/".join(sourcefile.parts[-3:])
    logger.info(f"Executing {last_3_layers}")
    with psycopg.connect(dbname) as conn:
        conn.execute(sql_stmt)


def main(dbname: str, source: Optional[str] = None):
    if source is None:
        source = os.path.dirname(
            os.path.abspath(inspect.getfile(inspect.currentframe()))
        )

    if isinstance(source, str):
        source = Path(source)
    sourcefiles = []
    if source.is_file():
        sourcefiles.append(source)
    elif source.is_dir():
        logger.debug(f"Skipping file {SKIP_FILE}, run this individually if desired")
        for item in source.walk():
            sourcefiles += [
                item[0] / sourcefile
                for sourcefile in item[2]
                if (sourcefile[-4:].lower() == ".sql" and SKIP_FILE not in sourcefile)
            ]
    sourcefiles.sort()
    logger.info(f"Found {len(sourcefiles)} sourcefiles")
    for file in sourcefiles:
        apply_source_file(dbname=dbname, sourcefile=file)


if __name__ == "__main__":
    parser = ArgumentParser(prog="setup_database")

    parser.add_argument("-d", "--dbname", type=str, required=True)
    parser.add_argument("-s", "--source", type=str)

    args = parser.parse_args()
    dbname = args.dbname
    source = args.source

    main(dbname=dbname, source=source)

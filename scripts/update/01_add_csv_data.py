from argparse import ArgumentParser
from itertools import repeat
from multiprocessing import Pool
from pathlib import Path
from typing import Tuple, Union

import pandas as pd
import psycopg
from tqdm import tqdm

CSVCOLS = [
    "Base station time stamp",
    "Course over ground",
    "Heading",
    "Latitude",
    "Longitude",
    "MMSI",
    "Navigational status (text)",
    "Speed over ground",
]

TABLECOLS = [
    "gps_timestamp",
    "course_over_ground",
    "heading",
    "latitude",
    "longitude",
    "mmsi",
    "nav_status",
    "speed_over_ground",
]

rename_cols = {ccol: tcol for ccol, tcol in zip(CSVCOLS, TABLECOLS, strict=True)}

COPY_STATEMENT = f"COPY stg.csv_data ( {','.join(TABLECOLS)} ) FROM STDIN CSV"


def upload_csv_to_db(dbname: str, csv_file: Union[str, Path]):
    conn = psycopg.connect(dbname)
    df = pd.read_csv(csv_file, usecols=CSVCOLS)

    with conn:
        with conn.cursor() as cursor:
            with cursor.copy(COPY_STATEMENT) as copy:
                copy.write(df.to_csv(header=False, index=False))


def star_upload_csv_to_db(arg: Tuple):
    return upload_csv_to_db(*arg)


def get_csv_paths(folder: str):
    datafolder = Path(folder)
    csv_files = []
    for item in datafolder.walk():
        csv_files += [
            item[0] / datafile
            for datafile in item[2]
            if datafile[-4:].lower() == ".csv"
        ]
    return csv_files


if __name__ == "__main__":
    parser = ArgumentParser(prog="Add CSV data")

    parser.add_argument("-d", "--dbname", type=str, required=True)

    source_group = parser.add_mutually_exclusive_group(required=True)
    source_group.add_argument("-c", "--csv_file", type=str)
    source_group.add_argument("-f", "--folder", type=str)

    parser.add_argument("-n", "--nworkers", type=int, default=4)

    args = parser.parse_args()
    dbname = args.dbname

    if (csv_file := args.csv_file) is not None:
        upload_csv_to_db(dbname=dbname, csv_file=csv_file)

    if (folder := args.folder) is not None:
        csv_files = get_csv_paths(folder)
        input_args = list(zip(repeat(dbname), csv_files))
        with Pool(args.nworkers) as p:
            r = list(
                tqdm(p.imap(star_upload_csv_to_db, input_args), total=len(input_args))
            )

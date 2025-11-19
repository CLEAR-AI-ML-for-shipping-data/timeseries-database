from argparse import ArgumentParser

import pandas as pd
import psycopg

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


def main(dbname: str, csv_file: str):
    conn = psycopg.connect(dbname)
    df = pd.read_csv(csv_file, usecols=CSVCOLS)

    with conn:
        with conn.cursor() as cursor:
            with cursor.copy(COPY_STATEMENT) as copy:
                copy.write(df.to_csv(header=False, index=False))


if __name__ == "__main__":
    parser = ArgumentParser(prog="Add CSV data")

    parser.add_argument("-d", "--dbname", type=str, required=True)
    parser.add_argument("-c", "--csv_file", type=str, required=True)

    args = parser.parse_args()

    main(dbname=args.dbname, csv_file=args.csv_file)

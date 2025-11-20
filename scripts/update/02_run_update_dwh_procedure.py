from argparse import ArgumentParser

import psycopg
from tqdm import trange


def get_number_of_rows_for_update(dbname: str):
    conn = psycopg.connect(dbname)
    with conn:
        res = conn.execute("SELECT COUNT(*) FROM stg.csv_data")
        row_1 = res.fetchone()
        return row_1[0]


def call_procedure(index_min: int, index_max: int, dbname: str):
    sql_stmt = f"CALL dwh.insert_into_dwh( {index_min}, {index_max} );"
    with psycopg.connect(dbname) as conn:
        _ = conn.execute(sql_stmt)


def star_call_procedure(args):
    call_procedure(*args)


if __name__ == "__main__":
    parser = ArgumentParser(prog="Add CSV data")

    parser.add_argument("-d", "--dbname", type=str, required=True)
    parser.add_argument("-b", "--batchsize", type=int, default=1_000_000)
    parser.add_argument("-n", "--nworkers", type=int, default=4)

    args = parser.parse_args()
    dbname = args.dbname
    batchsize = args.batchsize
    nworkers = args.nworkers

    nrows = get_number_of_rows_for_update(dbname)

    for i in trange(1, nrows + 1, batchsize):
        call_procedure(i, i + batchsize - 1, dbname)

    # # Maybe this parallel process can be used if we redesign the update procedure
    # input_args = []
    # for i in trange(1, nrows + 1, batchsize):
    #     input_args.append((i, i + batchsize - 1, dbname))
    # with Pool(nworkers) as p:
    #     result = list(
    #         tqdm(p.imap(star_call_procedure, input_args), total=len(input_args))
    #     )

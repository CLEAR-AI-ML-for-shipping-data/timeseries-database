# Timeseries based AIS database

This database contains the individual measuring points of available AIS data.
It is a PostgreSQL database.
We use PostGIS and TimescaleDB to deal with the geographic and timebased nature of the data, respectively.

The database consists of multiple layers:

1. staging layer (`stg`), which is a simple 1:1 copy of the original CSV data
2. data warehouse layer (`dwh`), where we denormalize the data to NF3
3. datamart layer (`dm`), which contains tables with useful information for analysis or other use

## Scripts

All scripts necessary to run the processes associated with this database are
located in the `scripts` folder.

### Creating the database

The creation of all tables, indices, stored procedures, etc. is governed by the
SQL scripts inside the `init` folder.
Creation scripts are grouped by schema, and are numbered in the order of which they should be run.
For example, the data warehouse should be created aftefr the staging schema, but before the datamart schema.
Therefore the data warehouse folder has prefix `03`.
Similarly, for the warehouse itself we first need to create the schema (`01`), then the tables (`02`).
After that we create the stored procedure to update the warehouse (`03`).

All these scripts can be called by executing the `init/setup_database.py` script with the database url and the location of the init scripts.

```bash
python scripts/init/setup_database.py \
    --dbname=postgresql://<username>:<password>@<hostname>:5432/<dbname> \
    --source=scripts/init
```

### Updating the database

#### Inserting data

Data can be inserted into the database through either a shell script with multiple calls to `psql`, or through a python script.

The easiest and most platform-independent way is the python script, which requires either a CSV file or a folder with CSV files to upload to the database.

```bash
python scripts/update/01_add_csv_data.py --dbname=<dburl> --csv_file=mydata.csv
python scripts/update/01_add_csv_data.py --dbname=<dburl> --folder=data_folder
```

For the Python script, we use Psycopg version 3, because that exposes the COPY utility through the Python API.
We also elected to not use SQLAlchemy, since the ORM functionality creates too much overhead for bulk inserting billions of rows, especially in the DWH stage with one-to-many relationships mapping to tens of thousands of rows.

#### From staging to data warehouse

Data in the data warehouse is normalized up to NF3.
It updates data in chunks of 1 million rows, so as to not timeout the database connection in the middle of updating.
The actual updating is done by calling the the stored procedure `dwg.insert_into_dwh`.
The python intermediary for this is `scripts/update/02_run_update_dwh_procedure.py`.
Before calling the stored procedure, this script will drop the index on the dwh.positions table, and rebuild it afterwards.
This is faster than inserting with the index on timestamp and ship_id still present.

#### Finding trajectories

The finding of trajectories happens in two stages.
First we establish the start and end points of what we consider trajectories by calling the `dm.find_voyages` procedure.
The ship_id and both timestamps are then stored in the table `dm.trajectory_limits`.
After that, we create an export table, which contains the entire trajectory as a linestring, as well as vectors of the different scalar values during this voyage.

## Suggestions for improvement

There are several things that can be done to improve the database:

1. Add timestamps and sourcefiles into the staging table. This would make it possible to run an update only on the new data.
2. Parallellize the normalization process. Currently this results in a deadlock when multiple calls want to insert the same ship into the ships table.
   1. a way around this would be to first select all ships. However running a SELECT DISTINCT mmsi over a billion row table is tricky. Maybe chunk this into sequential segments?
   2. Another way to speed this up is by running `SELECT mmsi from stg.csv_data GROUP BY mmsi`, which is much faster (?)
3. Build functionality to read CSV files directly from a zipfile, without the need to unzip the entire archive.

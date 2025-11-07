insert into dwh.ships (mmsi) select mmsi from (
  select t1.mmsi, ships.id from (select distinct mmsi from stg.csv_data) as t1
  left join dwh.ships
  on t1.mmsi = ships.mmsi
where ships.id is null
);

insert into dwh.positions (gps_position, ship_id, gps_timestamp, nav_status) select * from (
	select ST_Point(t1.longitude, t1.latitude, 4326) as gps_position
	, ships.id as ship_id
	, t1.gps_timestamp
	, t1.nav_status
	from stg.csv_data as t1
	left join dwh.ships as ships
	on t1.mmsi = ships.mmsi
)

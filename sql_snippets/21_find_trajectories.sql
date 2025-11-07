drop table if exists tmp_deltas;

create temp table tmp_deltas as (select ship_id
, gps_position
, gps_timestamp
, nav_status
, gps_timestamp - lag(gps_timestamp) over(
	partition by ship_id 
	order by gps_timestamp 
	rows between 1 preceding and current row
	)  as delta_t
, lag(nav_status) over(
	partition by ship_id 
	order by gps_timestamp 
	rows between 1 preceding and current row
	) as nav_status_prev

from dwh.positions);

-- Determine engine transitions and timegaps
drop table if exists tmp_transitions;

create temp table tmp_transitions as 
(
select d.*
, 	case when d.nav_status_prev != 'Engine' and d.nav_status = 'Engine' then 1 
	else 0 
	end as start_engine
, 	case when d.nav_status_prev = 'Engine' and d.nav_status != 'Engine' then 1 
	else 0 
	end as stop_engine

, case when delta_t > '15 min 0 sec' and d.nav_status_prev = 'Engine' and d.nav_status = 'Engine' then 1
	else 0
	end as start_after_gap

from tmp_deltas as d
);

-- Combine the starts and stops
drop table if exists tmp_trajectory_transitions;
create table tmp_trajectory_transitions as
(select m.*
from
(
select tt.ship_id
, tt.gps_position
, tt.gps_timestamp
, tt.nav_status
, greatest(start_engine, start_after_gap) as start_trajectory
, greatest(stop_engine
    -- The stop before a gap
	, lead(start_after_gap) over (
partition by ship_id
order by gps_timestamp
rows between current row and 1 following
) ) as stop_trajectory

from tmp_transitions as tt
) as m
where m.start_trajectory = 1 or m.stop_trajectory = 1
)
;


-- Remove the first datapoint of a ship if it is a stop point
drop table if exists tmp_numbered_transitions;

create temp table tmp_numbered_transitions as (
	select tt.* 
	, row_number() over(
		partition by ship_id
		order by gps_timestamp
	) as regular_rank
	
	from tmp_trajectory_transitions as tt
);

DELETE FROM tmp_numbered_transitions 
where stop_trajectory = 1 
  and regular_rank = 1
  ;
ALTER TABLE tmp_numbered_transitions
DROP COLUMN regular_rank;
-- We do not deal with voyages that have no final stop condition
-- We just set the stop datetime to 9999-12-31 00:00:00

-- select * from tmp_numbered_transitions


drop table if exists tmp_trajectory_boundaries;

create temp table tmp_trajectory_boundaries as (
	select t1.ship_id
	, t1.gps_timestamp as timestamp_start
	-- Select closest stop to start
	-- If the trajectory is open, set the stop datetime to infinity
	, coalesce( min(t2.gps_timestamp), timestamp 'infinity') as timestamp_stop

	-- A table with all the trajectory starts
	from (select * from tmp_numbered_transitions where start_trajectory = 1) as t1

	-- A table with all the trajectory stops
	left join (select * from tmp_numbered_transitions where stop_trajectory = 1) as t2
		on	t1.ship_id = t2.ship_id
		-- Do the less-or-equal comparison for points with both stop and start
		and t1.gps_timestamp <= t2.gps_timestamp
	
	group by t1.ship_id, t1.gps_timestamp
	
	order by t1.ship_id, t1.gps_timestamp
);

INSERT INTO dm.trajectory_limits (ship_id, datetime_start, datetime_stop) 

  select ship_id, timestamp_start, timestamp_stop from tmp_trajectory_boundaries
;



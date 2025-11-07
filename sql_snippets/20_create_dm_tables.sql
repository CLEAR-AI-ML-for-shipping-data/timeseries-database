create schema if not exists dm;

drop table if exists dm.trajectory_limits;

CREATE TABLE dm.trajectory_limits (
  id SERIAL NOT NULL,
  ship_id BIGINT,
  datetime_start TIMESTAMP WITHOUT TIME ZONE NOT NULL,
  datetime_stop TIMESTAMP WITHOUT TIME ZONE NOT NULL,

  PRIMARY KEY (id),
  FOREIGN KEY (ship_id) REFERENCES dwh.ships

)


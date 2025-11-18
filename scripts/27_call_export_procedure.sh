#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: ${0##*/} [ -d  DATABASE | -h ]
Connect to database DATABASE and run query.
    -d DATABASE   database connection string
    -h            display this help
EOF
}

DBNAME=""

while getopts hd: OPT; do
  case "$OPT" in
  d)
    DBNAME=$OPTARG
    ;;
  h)
    usage >&1
    exit 0
    ;;
  *)
    echo "Unexpected option: $1" >&2
    usage >&2
    exit 1
    ;;
  esac
done

if [[ "$DBNAME" == "" ]]; then
  echo "Database required"
fi

SHIPIDS=()
while read -r SHIPID; do
  SHIPIDS+=("$SHIPID")
done <<<"$(psql --dbname="$DBNAME" -c "select id from dwh.ships" --csv -t)"


# Perform the voyage finding per ship. This is done for 2 reasons
# 1) the positions table is indexed on ship_id and timestamp
# 2) Doing it for all the ships simultaneously takes too much time in a single transaction
N_SHIPS=${#SHIPIDS[@]}
echo "Found $N_SHIPS different ship_ids"
COUNTER=0

for SHIP_ID in "${SHIPIDS[@]}"; do
  ((COUNTER += 1))
  echo "Processing ship_id $SHIP_ID ($COUNTER / $N_SHIPS)..."
  psql --dbname="$DBNAME" -c "\timing on" -c "CALL dm.export_trajectories( $SHIP_ID );"
done

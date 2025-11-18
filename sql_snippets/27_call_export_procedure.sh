
DB_CONN=$1

SHIPIDS=()
while read -r SHIPID; do
  SHIPIDS+=("$SHIPID")
done<<<"$(psql $DB_CONN -c "select id from dwh.ships" --csv -t)"

N_SHIPS=${#SHIPIDS[@]}
echo "Found $N_SHIPS different ship_ids"
COUNTER=0

for SHIP_ID in "${SHIPIDS[@]}"; do
  ((COUNTER+=1))
  echo "Processing ship_id $SHIP_ID ($COUNTER / $N_SHIPS)..."
  psql "${DB_CONN}" -c "\timing on" -c "CALL dm.export_trajectories( $SHIP_ID );"
done



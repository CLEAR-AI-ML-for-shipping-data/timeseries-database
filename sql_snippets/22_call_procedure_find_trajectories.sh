usage() {
  cat <<EOF
Usage: ${0##*/} [-h] [-b BATCH_SIZE] [-s STAGETABLE] -d DATABASE 
Connect to database DATABASE and run data insertion.

Available options:

     -d      Database connection string
     -h      Show this help
EOF
}

DB_CONN=""

while getopts "d:h" OPT; do
  case $OPT in
  d)
    DB_CONN=${OPTNAME}
    ;;
  h)
    usage
    exit 0
    ;;
  *)
    echo "Invalid option ${OPT}"
    ;;
  esac
done

if [[ "${DB_CONN}" == "" ]]; then
  echo "Empty database string"
  usage >&2
fi

SHIPIDS=()
while read -r SHIPID; do
  SHIPIDS+=("$SHIPID")
done <<<"$(psql $DB_CONN -c "select id from dwh.ships" --csv -t)"

N_SHIPS=${#SHIPIDS[@]}
echo "Found $N_SHIPS different ship_ids"
COUNTER=0

for SHIP_ID in "${SHIPIDS[@]}"; do
  ((COUNTER += 1))
  echo "Processing ship_id $SHIP_ID ($COUNTER / $N_SHIPS)..."
  psql "${DB_CONN}" -c "\timing on" -c "CALL dm.find_voyages( $SHIP_ID );"
done

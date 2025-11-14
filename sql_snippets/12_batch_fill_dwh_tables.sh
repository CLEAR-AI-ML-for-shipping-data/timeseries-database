usage() {
  cat <<EOF
Usage: ${0##*/} [-h] [-b BATCH_SIZE] [-s STAGETABLE] -d DATABASE 
Connect to database DATABASE and run data insertion.

Available options:

     -b      Batch size, default is 1_000_000
     -d      Database connection string
     -h      Show this help
     -s      The staging table to which the data will be copied. The default is "stg.csv_data"
EOF
}

STAGETABLE="stg.csv_data"
BATCH_SIZE=1000000
DB_CONN=""

while getopts "b:d:hs:" opt; do
  case $opt in
  b)
    BATCH_SIZE=${OPTNAME}
    ;;
  d)
    DB_CONN=${OPTNAME}
    ;;
  h)
    usage
    exit 0
    ;;
  s)
    STAGETABLE=${OPTNAME}
    ;;
  *)
    echo "Invalid option ${opt}"
    ;;
  esac
done

if [[ "${DB_CONN}" == "" ]]; then
  echo "Empty database string"
  usage >&2
fi

echo "Counting rows of $STAGETABLE, this might take a while..."
ROWCOUNT=$(
  psql --dbname"${DB_CONN}" -c "SELECT COUNT(*) FROM ${STAGETABLE}" --csv -t
)

echo "Total number of rows: ${ROWCOUNT}"

TOTAL_BATCHES=$((($ROWCOUNT / BATCH_SIZE) + 1))
COUNTER=0

echo "Inserting $TOTAL_BATCHES batches of $BATCH_SIZE rows..."

for ((BATCH = 0; $BATCH < $TOTAL_BATCHES; BATCH++)); do
  ((COUNTER = BATCH + 1))
  ((STARTROW = BATCH * BATCH_SIZE + 1))
  ((ENDROW = COUNTER * BATCH_SIZE))
  echo "Inserting batch $COUNTER / $TOTAL_BATCHES (rows $STARTROW - $ENDROW)"
  psql --dbname="${DB_CONN}" -c "\timing on" -c "CALL dwh.insert_into_dwh( $STARTROW, $ENDROW );"
done

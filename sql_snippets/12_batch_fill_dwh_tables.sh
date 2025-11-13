DB_CONN=$1

STAGETABLE="stg.csv_data"
BATCH_SIZE=1000000

echo "Counting rows of $STAGETABLE, this might take a while..."
ROWCOUNT=$(
  psql "${DB_CONN}" -c "SELECT COUNT(*) FROM ${STAGETABLE}" --csv -t
)

# ROWCOUNT=1197729565

echo "Total number of rows: ${ROWCOUNT}"

TOTAL_BATCHES=$((($ROWCOUNT / BATCH_SIZE) + 1))
COUNTER=0

echo "Inserting $TOTAL_BATCHES batches of $BATCH_SIZE rows..."

# for STARTROW in $(seq 1 $BATCH_SIZE $ROWCOUNT); do
# for STARTROW in 1..$BATCH_SIZE..$ROWCOUNT; do
# for STARTROW in {1..${ROWCOUNT}..${BATCH_SIZE}}; do
for ((BATCH = 0; $BATCH < $TOTAL_BATCHES; BATCH++)); do
  # ((COUNTER+=1))
  ((COUNTER = BATCH + 1))
  ((STARTROW = BATCH * BATCH_SIZE + 1))
  ((ENDROW = COUNTER * BATCH_SIZE))
  echo "Inserting batch $COUNTER / $TOTAL_BATCHES (rows $STARTROW - $ENDROW)"
  psql "${DB_CONN}" -c "\timing on" -c "CALL dwh.insert_into_dwh( $STARTROW, $ENDROW );"
done

# for ((i = 0; i < 10; i++)); do
#   echo "$i"
# done

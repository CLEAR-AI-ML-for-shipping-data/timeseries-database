
DB_CONN=$1
DATA_FOLDER=$2

echo "Scanning $DATA_FOLDER for CSV files..."


# filename_length=${#ZIPFILE}
# extension=${ZIPFILE:filename_length-4:4}
# if [[ "$extension" == ".csv" ]]; then
#   echo "Is a csv file"
# fi

CSVFILES=()

while read -r CSVFILE; do
  # check for .csv extension
  filename_length=${#CSVFILE}
  extension=${CSVFILE:filename_length-4:4}
  if [[ "$extension" == ".csv" ]]; then
    CSVFILES+=("$CSVFILE")
  fi
done <<<"$(find "$DATA_FOLDER" -type f)"
# done <<<"$(unzip -Z -1 "$DATA_FOLDER")"

TOTAL_FILES=${#CSVFILES[@]}

echo "Found ${TOTAL_FILES} CSV files..."

for ((i = 0; i < ${#CSVFILES[@]}; i++)); do
  FILENAME=${CSVFILES[$i]}
  FILENUMBER=$((i + 1))
  echo "Copying file ${FILENAME} (${FILENUMBER}/${TOTAL_FILES})..."
  # We ignore errors, because sometimes there is a comma in the callsign, which messes up the column reading order
  psql -e ${DB_CONN} -c "\copy stg.csv_data (gps_timestamp, course_over_ground, heading, latitude, longitude, mmsi, nav_status, speed_over_ground) FROM program 'csvcut -c \"Base station time stamp\",\"Course over ground\",Heading,Latitude,Longitude,MMSI,\"Navigational status (text)\",\"Speed over ground\"  ""${FILENAME}""' WITH (ON_ERROR ignore, DELIMITER ',')"
done

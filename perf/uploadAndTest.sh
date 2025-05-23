#!/bin/bash

set -- ${@}

TARGET="${1:-dryrun}"
FILENUM="${2:-2}"
FILESIZE="${3:-99}"
[[ ${4} != M ]] && SIZEUNIT=K || SIZEUNIT=M
BMARK=${TARGET}_${FILENUM}_${FILESIZE}${SIZEUNIT}

. upload_env.sh

BEE_URL="${BEE_URL:-http://localhost:1633}"

TESTSCRIPT=StorageBeat.yml
OVERRIDES="--overrides '{\"config\":{\"phases\":[{\"duration\":$((FILENUM*2)),\"arrivalCount\":${FILENUM}}]}}'"
TIMESTAMP=$(date +%s)

mkdir -p tests
rm -f tests/current_payload_${BMARK}.csv

# $1 is target, $2 is random file id
upload() {
  case $1 in
    swarm)
      STAMP=$(swarm-cli stamp list --least-used --limit 1 --quiet --hide-usage --bee-api-url $BEE_URL)
      if [[ -z "${STAMP}" ]]; then
        echo "You do not have any stamps."
        exit 1
      fi
      UPLOAD="swarm-cli upload tests/random_data_file_${2} --stamp $STAMP --quiet --bee-api-url $BEE_URL"
      ;;
    arweave)
      UPLOAD="ardrive upload-file --local-path tests/random_data_file_${2} -F $ARDRIVE_FOLDER -w $ARDRIVE_WALLET --turbo | jq -r '.created[0].dataTxId'"
      ;;
    s3)
      # Actual upload
      mc -q cp tests/random_data_file_$2 $S3_PATH/ > /dev/null
      # Getting download link
      UPLOAD="mc share download --expire 2h $S3_PATH/random_data_file_${2} | grep Share | sed 's/.*\/\/[^\/]*\///'"
      ;;
    ipfs)
      UPLOAD="pinata upload tests/random_data_file_${2} | jq -r '.cid'"
      ;;
    *)
      UPLOAD="echo $1, file random_data_file_${2}"
      ;;
  esac

  eval "$UPLOAD"
}

for ((i=1; i<=FILENUM; i++)); do
  dd if=/dev/urandom of=tests/random_data_file bs=1${SIZEUNIT} count=${FILESIZE} conv=fsync &> /dev/null
  #get fileid from first alpha numeric symbols in generated file
  FILEID=$(tr -dc A-Za-z0-9 < tests/random_data_file | head -c 13)
  cp tests/random_data_file tests/random_data_file_${FILEID}
  upload $TARGET $FILEID >> tests/current_payload_${BMARK}.csv
  rm tests/random_data_file_${FILEID}
done

cp tests/current_payload_${BMARK}.csv tests/payload_${BMARK}_${TIMESTAMP}.csv

# If target is IPFS run garbage collector to make sure the files won't be dowloaded from cache
if [ $TARGET == "ipfs" ]; then
  ipfs repo gc > /dev/null
fi

if [ $TARGET != "dryrun" ]; then
  systemd-run --user --on-active=3600 -d artillery run -o tests/report_${BMARK}_${TIMESTAMP}.json -q -e $TARGET -v '{"payload":"tests/current_payload_'${BMARK}'.csv"}' ${OVERRIDES} $TESTSCRIPT 
else
  echo artillery run -o tests/report_${BMARK}_${TIMESTAMP}.json -q -e $TARGET -v '{"payload":"tests/current_payload_'${BMARK}'.csv"}' --overrides '{"config":{"phases":[{"duration":'${FILENUM}',"arrivalRate":1}]}}' $TESTSCRIPT
fi
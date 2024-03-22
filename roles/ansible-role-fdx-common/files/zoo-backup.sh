#!/usr/bin/env bash

set -eE
trap clean_up ERR


#################
### FUNCTIONS ###
#################

clean_up() {
    log "ERROR: Cleaning up due to error: $(caller), sending email to $email"
    echo -e "Subject: Script failed due to error\nzoo_backup.sh was killed due to an error\n$(caller)" | /usr/sbin/sendmail -r $email $email

    if [ -f 'zoo*json' ]; then
      rm zoo*json
    fi
    exit 1
}

function log {
    echo $1 | tee >(logger -t "${logger_prefix}")
}

function upload_azure() {
  log "File to upload $1 for environment $2"
  log "Current directory $PWD"

  FILENAME=${1}
  FILEENV=${2}

  export AZURE_STORAGE_ACCOUNT="zookeeperbackupu12wqosa"
  export AZURE_CONTAINER_NAME="zoobackup/${FILEENV}"
  export AZURE_ACCESS_KEY="RihqiCH+rcA+k29p1c9ohRqb+uFepm0x4omMeqYZJz5DruHvXYr/WGYTC+Fh9TkHF187Uj351Lh/+AStvH/c5Q=="

  authorization="SharedKey"

  HTTP_METHOD="PUT"
  request_date=$(TZ=GMT date "+%a, %d %h %Y %H:%M:%S %Z")
  storage_service_version="2015-02-21"

  # HTTP Request headers
  x_ms_date_h="x-ms-date:$request_date"
  x_ms_version_h="x-ms-version:$storage_service_version"
  x_ms_blob_type_h="x-ms-blob-type:BlockBlob"

  FILE_LENGTH=$(wc --bytes < ${FILENAME})
  FILE_TYPE=$(file --mime-type -b ${FILENAME})
  #FILE_MD5=$(md5sum -b ${FILENAME} | awk '{ print $1 }')
  FILE_MD5=${FILENAME}

  # Build the signature string
  canonicalized_headers="${x_ms_blob_type_h}\n${x_ms_date_h}\n${x_ms_version_h}"
  canonicalized_resource="/${AZURE_STORAGE_ACCOUNT}/${AZURE_CONTAINER_NAME}/${FILE_MD5}"

  #######
  # From: https://docs.microsoft.com/en-us/rest/api/storageservices/authentication-for-the-azure-storage-services
  #
  #StringToSign = VERB + "\n" +
  #               Content-Encoding + "\n" +
  #               Content-Language + "\n" +
  #               Content-Length + "\n" +
  #               Content-MD5 + "\n" +
  #               Content-Type + "\n" +
  #               Date + "\n" +
  #               If-Modified-Since + "\n" +
  #               If-Match + "\n" +
  #               If-None-Match + "\n" +
  #               If-Unmodified-Since + "\n" +
  #               Range + "\n" +
  #               CanonicalizedHeaders +
  #               CanonicalizedResource;
  string_to_sign="${HTTP_METHOD}\n\n\n${FILE_LENGTH}\n\n${FILE_TYPE}\n\n\n\n\n\n\n${canonicalized_headers}\n${canonicalized_resource}"

  # Decode the Base64 encoded access key, convert to Hex.
  decoded_hex_key="$(echo -n $AZURE_ACCESS_KEY | base64 -d -w0 | xxd -p -c256)"

  # Create the HMAC signature for the Authorization header
  signature=$(printf  "$string_to_sign" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$decoded_hex_key" -binary | base64 -w0)

  authorization_header="Authorization: $authorization $AZURE_STORAGE_ACCOUNT:$signature"
  #OUTPUT_FILE="https://${AZURE_STORAGE_ACCOUNT}.blob.core.windows.net/${AZURE_CONTAINER_NAME}/${FILE_MD5}"
  OUTPUT_FILE="https://${AZURE_STORAGE_ACCOUNT}.blob.core.windows.net/${AZURE_CONTAINER_NAME}/${FILENAME}"

  curl -X ${HTTP_METHOD} \
      -T ${FILENAME} \
      -H "$x_ms_date_h" \
      -H "$x_ms_version_h" \
      -H "$x_ms_blob_type_h" \
      -H "$authorization_header" \
      -H "Content-Type: ${FILE_TYPE}" \
      ${OUTPUT_FILE}

  if [ $? -eq 0 ]; then
      echo ${OUTPUT_FILE}
  fi;
}


function zookeeper_check {

  #**************************
  #Declare Variables
  #**************************

  #declare -a serverArray=()
  declare -a uniq_zx
  declare -A uniq_tmp

  # for Azure the property file is zookeeper.properties and for On-Prem its zookeeper_chr.properties
  # the filename is formed according to the environment

  filename="/etc/kafka/zookeeper_chr.properties"

  if [ ! -f "$filename" ]; then
    filename="/etc/kafka/zookeeper.properties"
  fi

  # Check if zookeeper file exists
  if [ ! -f "$filename" ]; then
    log "Zookeeper file $filename not found, patching will not continue"
    exit 1
  fi

  follower=0
  leader=0
  totalzoo=0

  log "Reading zookeeper property file $filename"
  zooleader=""
  var="$(grep ^server $filename | awk -F\= '{print $2}' | awk -F: '{print $1}')"
  auth="$(grep ^authProvider $filename | awk -F\= '{print $2}' | awk -F: '{print $1}')"

  echo "zookeeperfile..." $filename
  echo "logging..." $var

  for name in $var
  do
    # Check if the host name is incorrect (less than 5)
    if [ ${#name} -lt 5 ]; then
      log "Zookeeper node name $name possibly incorrect, verify if properties file has correct hostnames"
      break
    fi

    let "totalzoo+=1"

    log "Getting status of zookeeper $name"
    result=$(echo stat|nc $name 2181|grep 'Mode\|Zxid')

    shopt -s nocasematch

    # check if the zookeeper node is the leader, if yes then initiate backup
    if [[ $result =~ "leader" ]]; then
      zooleader=$name
      log "Server $name with Zxid $zxid is a leader..."
    fi
  done

  # check if there is a zookeeper leader and if the zookeeper is secured and start backup
  if [  -z "$zooleader" ]; then
    log "No Zookeeper leader found in the list of servers, cannot initiate backup"
    exit 1
  fi

  # backup is initiated only from zookeeper leader
  #if [[ "$HOSTNAME" != "$name" ]]; then
  #  log "Backup is only initiated from leader, $name is not the leader"
  #  exit 0
  #fi

  cur_dir=`dirname $0`
  jsonfile=$(basename -- $filename)-$(date +"%Y%m%dT%H%M").json
  clientconfigfile=$cur_dir/$(basename -- $filename).conf
  log "zookeeper backup file (json)  -> $jsonfile"
  log "zookeeper secure config file -> $clientconfigfile"

  if [ -z "$auth" ]; then
    log "Zookeeper file $file is unsecured"
    # initiate backup
    $cur_dir/zookeeperbk dump unsecure -z $zooleader:2181 > $cur_dir/$jsonfile
  else
    log "Zookeeper file $file is secured"

    # exit if zookeeper client config file not found
    if [ ! -f "$clientconfigfile" ]; then
      log "Zookeeper client config file $clientconfigfile not found"
      exit 1
    fi
    # initiate backup
    $cur_dir/zookeeperbk dump $clientconfigfile -z $zooleader:2181 > $cur_dir/$jsonfile
  fi

  # loop through the output directory and upload files to Azure blob storage and
  # delete files
  cur_dir=`dirname $0`

  for file in $cur_dir/*json
  do
    jsonfile=$(basename -- $file)
    log "file to upload $jsonfile.........."
    # Using regex to extract the file environment variable
    file_env=$(echo $jsonfile | sed -r 's/^([a-z]+)\.([a-z]+)\.([a-z]+)(.*)/\3/')
    log "file environment $file_env"

    # Exit if environment not set in the file
    if [ -z "${file_env}" ]; then
      log "Environment not found in the file $jsonfile, exiting..."
      exit 1;
    fi

    # upload file and delete
    upload_azure $jsonfile $env; ec=$?
    rm $jsonfile

  done
}

############
### MAIN ###
############

###################
### GLOBAL VARS ###
###################

logger_prefix="zoo-backup.sh"
email="rahul.chakrabarty@chrobinson.com"
scriptdir="/etc/chrobinson"

cd $scriptdir

shopt -s nocasematch

# Hostnames have different naming convention for Azure and on-prem, this check ensures that when VMs are deployed
# on on-prem it fetches the classifications correctly

if [[ $HOSTNAME =~ "rh" ]]; then
  env=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)-([a-z]+)([[:digit:]]+)\.(.*)/\3/')
  env="az"$env

elif [[ $HOSTNAME =~ "lin" ]]; then
  env=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)\.(.*)/\3/')
  env="op"$env
fi

echo "For environment: $env"

log "=============================================================="
log "Starting zookeeper backup..."
log "os=${os} region=${region} env=${env} type=${type} number=${number} domain=${domain}"

# check if all necessary files exists
declare -a filearr=("$scriptdir/zoo-backup.sh" "$scriptdir/zookeeperbk" "$scriptdir/zoocreeper-1.0-SNAPSHOT.jar" "$scriptdir/pre_update.sh" "/usr/sbin/sendmail")

for file in "${filearr[@]}"
do
  if [ ! -f "$file" ]; then
    log "File $file does not exists, cannot continue with backup"
    exit 1;
  fi
done

# call pre_update.sh to validate that zookeeper cluster is healthy before initiating backup
(. $scriptdir/pre_update.sh)
ec=$?

if [ "$ec" -eq 1 ]; then
  log "pre_update.sh script failed, zookeeper cluster not healthy, cannot initiate backup"
  exit 1;
fi

# call function to initiate backup
zookeeper_check

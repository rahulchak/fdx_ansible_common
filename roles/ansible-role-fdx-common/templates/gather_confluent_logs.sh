#!/usr/bin/env bash
trap clean_up ERR

#################
### FUNCTIONS ###
#################

clean_up() {
    log "ERROR: cleaning up due to error on line $(caller)"
    exit 1
}

function log {
    echo $1 | tee >(logger -t "${logger_prefix}")
}

###################
### GLOBAL VARS ###
###################

logger_prefix="gather_confluent_logs.sh"
tackd_endpoint="https://tackd.dc2.prd.dds.chr8s.io"
current_date=$(date +%Y-%m-%d)
tar_file="${HOSTNAME}-${current_date}.tar.gz"
tackd_upload_key={{ tackd_upload_key }}
tackd_upload_secret={{ tackd_upload_secret }}
tackd_expires=1y

####################
### RUNTIME VARS ###
####################

if [[ $HOSTNAME =~ "rh" ]]; then
  region=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)-([a-z]+)([[:digit:]]+)\.(.*)/\2/')
  env=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)-([a-z]+)([[:digit:]]+)\.(.*)/\3/')
  type=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)-([a-z]+)([[:digit:]]+)\.(.*)/\4/')
  number=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)-([a-z]+)([[:digit:]]+)\.(.*)/\5/')
  tar_folder="/mnt"
  env_prefix="az"
elif [[ $HOSTNAME =~ "lin" ]]; then
  region=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)\.(.*)/\2/')
  env=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)\.(.*)/\3/')
  type=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)\.(.*)/\7/')
  number=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)\.(.*)/\8/')
  tar_folder="/tmp"
else
  log "Server name doesn't match"
  exit 1
fi

# Identify log files and service names based on servername
if [[ "$type" == "conne" ]]; then
  log_files="/var/log/kafka/connect.log*"
  service=connect

elif [[ "$type" == "schem" ]]; then
  log_files="/var/log/confluent/schema-registry/schema-registry.log*"
  service=schema_registry

elif [[ "$type" == "broke" ]] || [[ "$type" == "b" ]]; then
  log_files="/var/log/kafka/server.log* /var/log/kafka/controller.log* /var/log/kafka/kafka-authorizer.log*"
  service=broker

elif [[ "$type" == "zooke" ]]; then
  log_files="/var/log/kafka/zookeeper-server.log*"
  service=zookeeper

# Onprem logs are in a different location
elif [[ "$type" == "s" ]] || [[ "$type" == "r" ]]; then
  log_files="/var/log/schema-registry/schema-registry.log.?"
  service=schema_registry

elif [[ "$type" == "z" ]]; then
  log_files="/var/log/kafka/server.log.?"
  service=zookeeper
else
  echo "Unable to match server service type"
  exit 2
fi

############
### MAIN ###
############

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Request case number, or accept a newline
echo -n "Please enter Confluent case number: "
read case

if [[ "${case}" != "" ]]; then
  confluent_case=",case:${case}"
fi

log "Beginning log collection: region=${region} env=${env_prefix}${env} type=${type} number=${number} service=${service}"

# Tar up log files
log "Tar'ing up log files..."
tar -czf ${tar_folder}/${tar_file} ${log_files} >/dev/null 2>&1 || ( export ret=$?; [[ $ret -eq 1 ]] || exit "$ret" )

# Upload tar
log "Uploading tar files..."
output=$(curl -u ${tackd_upload_key}:${tackd_upload_secret} --progress-bar -XPOST --data-binary @${tar_folder}/${tar_file} \
"${tackd_endpoint}/upload?filename=${tar_file}&expires=${tackd_expires}&tags=region:${region},env:${env_prefix}${env},type:${type},number:${number},service:${service},time:$(date +%H%M),date:${current_date}${confluent_case}")

# Clean up tar file
if [ -f "${tar_folder}/${tar_file}" ]; then
  log "Removing tar'd files..."
  rm -fv ${tar_folder}/${tar_file} >/dev/null
fi

# Return response from tackd
echo "Tackd Response:"
echo ${output}
echo

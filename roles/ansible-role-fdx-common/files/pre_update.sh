#!/usr/bin/env bash
trap clean_up ERR


#################
### FUNCTIONS ###
#################

clean_up() {
    log "ERROR: cleaning up due to error: $(caller)"
    exit 1
}

function log {
    echo $1 | tee >(logger -t "${logger_prefix}")
}

function broker_check {
    log "Checking broker health"
    log "Getting offline partitions"
    offline=$(kafka-topics --command-config /etc/kafka/client.properties --bootstrap-server localhost:9092 --describe --unavailable-partitions | wc -l)

    log "Getting URP's"
    urp=$(kafka-topics --command-config /etc/kafka/client.properties --bootstrap-server localhost:9092 --describe --under-replicated-partitions | wc -l)

    if [ "$urp" -gt "0" ] || [ "$offline" -gt "0" ]
    then
        log "Detected issue with brokers: urp=${urp} offline=${offline}"
        log "The kafka cluster is out-of-sync, patching will not continue"
        exit 1
    fi
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

  log "Checking zookeeper health"

  var="$(grep ^server $filename | awk -F\= '{print $2}' | awk -F: '{print $1}')"

  prev_zxid=""
  zxid_count=0

  for name in $var
  do
    # Check if the host name is incorrect (less than 5)
    if [ ${#name} -lt 5 ]; then
      log "Zookeeper node name $name possibly incorrect, patching will not continue"
      break
    fi

    let "totalzoo+=1"

    log "Getting status of zookeeper $name"
    result=$(echo stat|nc $name 2181|grep 'Mode\|Zxid')

    # Applying RegEx to extract the Zxid
    zxid=$(echo $result| sed -r 's/^(.*?):(.*?)\Mode(.*)/\2/')

    # Compare zxid's
    if [[ "${prev_zx}" != "" ]]
    then
      if [[ "${zxid}" != "${prev_zx}" ]]
      then
        zxid_count=$(( zxid_count + 1 ))
      fi
    else
      prev_zx=${zxid}
      zxid_count=1
    fi

    shopt -s nocasematch

    if [[ $result =~ "follower" ]]; then
      log "Server $name with Zxid $zxid is a follower..."
      let "follower+=1"

    elif [[ $result =~ "leader" ]]; then
      log "Server $name with Zxid $zxid is a leader..."
      let "leader+=1"

    else
      log "Server $name with Zxid $zxid has no status..."
    fi
  done

  # Check zookeeper health and fail if
  #  - No leader is found
  #  - Total zookeeper nodes dont match the number of leader & followers
  #  - Multiple Zxid found

  if [ $leader -eq 0 ] || [ $leader -gt 1 ]; then
    log "Leader count $leader - must be exactly 1, patching will not continue"
    exit 1
  fi

  #if [ $(($leader + $follower)) -ne ${#serverArray[@]} ]; then
  if [ $(($leader + $follower)) -ne $totalzoo ]; then
    log "One or more zookeeper nodes are down, patching will not continue"
    exit 1
  fi

  # Check if array contains unique Zxid - if not possibility of
  # duplicate leaders

  if [ ${zxid_count} -ne 1 ]; then
    log "Multiple Zxid found check previous log entries to determine the server with different Zxid, patching will not continue"
    exit 1
  fi
}

function connect_check {
  log "Checking connect health"
  filename="/etc/chrobinson/ansible_group_inventory"
  port=8083

  if [ -f "$filename" ]; then
    cat $filename | tr ',' '\n' | tr -d '"[ ' | tr ']' '\n' | while read line
    do
      # If line is not empty
      if [ ! -z "$line" ]; then

        # Check if the host name is incorrect (less than 5)
        if [ ${#line} -lt 5 ]; then
          log "Node name $name possibly incorrect, patching will not continue"
          break
         fi

         log "Checking status of connect node $line port $port"
         status=$(curl -s https://$line:$port)

         if [[ $status =~ "version" ]]; then
           log "Connect end point $line:$port working"
         else
           log "Connect end point $line:$port not working, patching will not continue"
           exit 1
         fi
      fi
  done
  else
    log "Connect hosts file not found, patching will not continue"
    exit 1
  fi
}


function schema_check {
  log "Checking schema health"
  filename="/etc/chrobinson/ansible_group_inventory"
  port=8081

  if [ -f "$filename" ]; then
    cat $filename | tr ',' '\n' | tr -d '"[ ' | tr ']' '\n' | while read line
    do
      echo $line
      # If line is not empty
      if [ ! -z "$line" ]; then
        # Check if the host name is incorrect (less than 5)
        if [ ${#line} -lt 5 ]; then
          log "Node name $name possibly incorrect, patching will not continue"
          break
        fi

        log "Checking status of connect node $line port $port"
        status=$(curl -s https://$line:$port)

        if [[ $status =~ "{}" ]]; then
          log "Schema Registry end point $line:$port working"
        else
          log "Schema Registry end point $line:$port not working, patching will not continue"
          exit 1
        fi
      fi
    done
  else
    echo 'file not found'
    log "Connect hosts file not found, patching will not continue"
    exit 1
  fi
}

############
### MAIN ###
############

###################
### GLOBAL VARS ###
###################

logger_prefix="pre_update.sh"
connect_service="confluent-kafka-connect.service"
schema_service="confluent-schema-registry.service"
broker_service="confluent-server.service"
zoo_service="confluent-zookeeper.service"

shopt -s nocasematch

# Hostnames have different naming convention for Azure and on-prem, this check ensures that when VMs are deployed
# on on-prem it fetches the classifications correctly

if [[ $HOSTNAME =~ "rh" ]]; then
  os=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)-([a-z]+)([[:digit:]]+)\.(.*)/\1/')
  region=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)-([a-z]+)([[:digit:]]+)\.(.*)/\2/')
  env=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)-([a-z]+)([[:digit:]]+)\.(.*)/\3/')
  type=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)-([a-z]+)([[:digit:]]+)\.(.*)/\4/')
  number=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)-([a-z]+)([[:digit:]]+)\.(.*)/\5/')
  domain=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)-([a-z]+)([[:digit:]]+)\.(.*)/\6/')

elif [[ $HOSTNAME =~ "lin" ]]; then
  os=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)\.(.*)/\1/')
  region=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)\.(.*)/\2/')
  env=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)\.(.*)/\3/')
  type=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)\.(.*)/\7/')
  number=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)\.(.*)/\8/')
  domain=$(echo $HOSTNAME | sed -r 's/^([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)([a-z]+)([[:digit:]]+)\.(.*)/\9/')

else
  log "Server name doesn't match"
  exit 1
fi

# If the repective service is disabled then continue with the patching
if [[ "$HOSTNAME" == *"conne"* ]]; then
  service=${connect_service}

elif [[ "$HOSTNAME" == *"schem"* ]]; then
  service=${schema_service}

elif [[ "$HOSTNAME" == *"broke"* ]]; then
  service=${broker_service}

elif [[ "$HOSTNAME" == *"zooke"* ]]; then
  service=${zoo_service}

fi

if [[ $(systemctl status ${service}|grep enabled) ]]; then
  log "Service $service is enabled, continue with pre-checks"
else
  log "Service $service is disabled, pre-checks are not to be executed, continue with patching"
  exit 0
fi


log "os=${os} region=${region} env=${env} type=${type} number=${number} domain=${domain}"
case `echo $type` in
  broke)
    broker_check
    ;;
  zooke| z)
    zookeeper_check
    ;;
  conne)
    connect_check
    ;;
  schem)
    schema_check
    ;;
  *)
    echo "Failed to match server type"
    exit 1
    ;;
esac

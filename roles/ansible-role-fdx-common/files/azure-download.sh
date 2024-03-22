 #!/usr/bin/env bash


usage ()  {
    echo
    echo "Usage: $0 FILENAME FILEENV FILE_TYPE"
    echo " -FILENAME                    Filename to download from the blob storage"
    echo " -FILEENV                     The environment which is the directory in the storage container under which the file exists"
    echo " -FILE_TYPE                   File content type defaults to text/plain if not passed as parameter"
    echo
    echo "MANDATORY FIELDS: FILENAME FILEENV"
    exit 1
}

check_not_null() {
    [ -z "$2" ]  && echo "Did not specify mandatory arg: '$1'" && usage
}


function downloadfile() {

  # Build the signature string
  #canonicalized_headers="${x_ms_date_h}\n${x_ms_version_h}"
  canonicalized_headers="${x_ms_blob_type_h}\n${x_ms_date_h}\n${x_ms_version_h}"
  canonicalized_resource="/${STORAGE_ACCOUNT}/${STORAGE_CONTAINER}/${FILENAME}"

  string_to_sign="${HTTP_METHOD}\n\n\n\n\n${FILE_TYPE}\n\n\n\n\n\n\n${canonicalized_headers}\n${canonicalized_resource}"

  # Decode the Base64 encoded access key, convert to Hex.

  decoded_hex_key="$(echo -n $STORAGE_KEY | base64 -d -w0 | xxd -p -c256)"

  # Create the HMAC signature for the Authorization header
  signature=$(printf "$string_to_sign" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$decoded_hex_key" -binary | base64 -w0)

  authorization_header="Authorization: $authorization $STORAGE_ACCOUNT:$signature"
  DOWNLOAD_FILE="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${STORAGE_CONTAINER}/${FILENAME}"

  curl -H "$x_ms_date_h" \
       -H "$x_ms_version_h" \
       -H "$x_ms_blob_type_h" \
       -H "$authorization_header" \
       -H "Content-Type: ${FILE_TYPE}" \
       -f ${DOWNLOAD_FILE} -o ${FILENAME}
}

## MAIN ###

FILENAME=${1}
FILEENV=${2}
FILE_TYPE=${3}

# if file type is not passed as parameter then it defaults to text/plain
if [ -z "$FILE_TYPE" ]; then
  FILE_TYPE="text/plain"
fi

# env, topic, user and role are required parameters
check_not_null  "FILENAME" $FILENAME
check_not_null  "FILEENV" $FILEENV

authorization="SharedKey"

HTTP_METHOD="GET"
request_date=$(TZ=GMT date "+%a, %d %h %Y %H:%M:%S %Z")
storage_service_version="2009-09-19"

# HTTP Request headers
x_ms_date_h="x-ms-date:$request_date"
x_ms_version_h="x-ms-version:$storage_service_version"
x_ms_blob_type_h="x-ms-blob-type:BlockBlob"

export STORAGE_ACCOUNT="zookeeperbackupu12wqosa"
export STORAGE_CONTAINER="zoobackup/${FILEENV}"
export STORAGE_KEY="xxx"

downloadfile

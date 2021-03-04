#!/usr/bin/env bash

reverse-hex-endian () {
  # Given a 4-byte hex integer, reverse endianness
  while read -r -d '' -N 8 INTEGER; do
    echo "$INTEGER" | sed -E 's/(..)(..)(..)(..)/\4\3\2\1/'
  done
}

decode-hex-int () {
  # decode little-endian hex integer
  while read -r -d '' -N 8 INTEGER; do
    BIG_ENDIAN_HEX=$(echo "$INTEGER" | reverse-hex-endian)
    echo "$((16#$BIG_ENDIAN_HEX))"
  done
}

encode-int () {
  # Encode an integer as 4 bytes in little endian and return as hex
  INT="$1"
  # Source: https://stackoverflow.com/a/9955198
  printf "%08x" "$INT" | sed -E 's/(..)(..)(..)(..)/\4\3\2\1/' 
}

encode () {
  # Encode a packet type and payload for the rcon protocol
  TYPE="$1"
  PAYLOAD="$2"
  REQUEST_ID="$3"
  PAYLOAD_LENGTH="${#PAYLOAD}" 
  TOTAL_LENGTH="$((4 + 4 + PAYLOAD_LENGTH + 1 + 1))"

  OUTPUT=""
  OUTPUT+=$(encode-int "$TOTAL_LENGTH")
  OUTPUT+=$(encode-int "$REQUEST_ID")
  OUTPUT+=$(encode-int "$TYPE")
  OUTPUT+=$(echo -n "$PAYLOAD" | xxd -ps)
  OUTPUT+="0000"
  
  echo -n "$OUTPUT" | xxd -ps -r
}

read-response () {
  # read next response packet and return the payload text
  IN_PIPE="$1"
  # HEX_LENGTH=$(head -c4 "$IN_PIPE" | xxd -ps | reverse-hex-endian)
  HEX_LENGTH=$(head -c4 <&3 | xxd -ps | reverse-hex-endian)
  LENGTH=$((16#$HEX_LENGTH))

  RESPONSE_PAYLOAD=$(head -c $LENGTH <&3 | xxd -ps)
  echo -n "$RESPONSE_PAYLOAD"
}

response-request-id () {
  echo -n "${1:0:8}" | decode-hex-int
}

response-type () {
  echo -n "${1:8:8}" | decode-hex-int
}

response-payload () {
  echo -n "${1:16:-4}" | xxd -r -ps
}

login () {
  PASSWORD="$1"
  encode 3 "$PASSWORD" 12 >&3

  RESPONSE=$(read-response "$IN_PIPE")

  RESPONSE_REQUEST_ID=$(response-request-id "$RESPONSE")
  if [ "$RESPONSE_REQUEST_ID" -eq -1 ] || [ "$RESPONSE_REQUEST_ID" -eq 4294967295 ]; then
    echo "Authentication failed: Wrong RCON password" 1>&2
    return 1
  fi
}

run-command () {
  COMMAND="$1"
  
  # encode 2 "$COMMAND" 13 >> "$OUT_PIPE"
  encode 2 "$COMMAND" 13 >&3

  RESPONSE=$(read-response "$IN_PIPE")
  response-payload "$RESPONSE"
}

rcon-command () {
  HOST="$1"
  PORT="$2"
  PASSWORD="$3"
  COMMAND="$4"

  # Open a TCP socket
  # Source: https://www.xmodulo.com/tcp-udp-socket-bash-shell.html
  exec 3<>/dev/tcp/"$HOST"/"$PORT"

  login "$PASSWORD" || return 1
  run-command "$COMMAND"

  # Close the socket
  exec 3<&-
  exec 3>&-
}


HOST="$1"
PORT="$2"
PASSWORD="$3"
COMMAND="$4"

rcon-command "$HOST" "$PORT" "$PASSWORD" "$COMMAND"

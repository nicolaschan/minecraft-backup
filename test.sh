#!/bin/bash

START_TIMESTAMP=1501484400

ITERATIONS=1000
MINUTE_INTERVAL=30
MINUTES_SINCE_START=0

if [[ $1 != "" ]]; then
  ITERATIONS=$1
fi

for (( c=1; c<=$ITERATIONS; c++ )); do
  TIMESTAMP=$(( START_TIMESTAMP + MINUTES_SINCE_START * 60 ))
  FILE_NAME=$(date -d "@$TIMESTAMP" +%F_%H-%M-%S)
  ./backup.sh -q -i /home/nicolas/privatesurvival/world -o /home/nicolas/backups -f $FILE_NAME
  (( MINUTES_SINCE_START += MINUTE_INTERVAL ))
done

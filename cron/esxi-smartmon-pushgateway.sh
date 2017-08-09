#!/bin/bash

if [ "$#" -ne 1 ]; then
  echo "Illegal number of parameters"
  exit
fi

ESXIHOST=$1
INSTANCE=$1

curl -X DELETE --connect-timeout 5 --max-time 60 http://localhost:9091/metrics/job/smartmon/instance/$INSTANCE
/usr/local/bin/smartmon.sh $ESXIHOST | curl --connect-timeout 5 --max-time 60 --data-binary @- http://localhost:9091/metrics/job/smartmon/instance/$INSTANCE

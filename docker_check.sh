#!/bin/bash

docker-compose ps
while :
do
  PS_COUNT=`docker-compose ps | grep -c Up`
  sleep 1
  if [ $PS_COUNT -lt 2 ]; then
    docker-compose down
    break
  fi
done
#!/bin/bash

while :
do
  PS_COUNT=`docker compose ps | grep -c running`
  sleep 1
  if [ $PS_COUNT -lt 2 ]; then
    docker compose down
    break
  fi
done
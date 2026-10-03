#!/bin/bash
# Passive: log the phone's USB identity whenever it changes. Never sends commands to the phone.
last=""
while true; do
  cur=$(lsusb | grep -oiE "18d1:d00d|1004:[0-9a-f]{4}|0525:[0-9a-f]{4}|18d1:[0-9a-f]{4}" | head -1)
  [ -z "$cur" ] && cur=none
  if [ "$cur" != "$last" ]; then echo "$(date '+%F %T') $cur" >> ${LOG:-./usbwatch.log}; last=$cur; fi
  sleep 5
done

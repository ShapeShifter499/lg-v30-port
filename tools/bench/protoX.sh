#!/bin/sh
# 2x (20 spaced sessions, then 20 back-to-back) -- the sequence that reset bl10
: > /home/user/camrace.log; : > /home/user/camvf.log
for rep in 1 2; do
  sh /home/user/camvfstress.sh 20
  echo "$(date +%T) rep $rep cold done" >> /home/user/camrace.log; sync
  sh /home/user/camrace.sh 20 0
done
echo "$(date +%T) ALLDONE" >> /home/user/camrace.log; sync

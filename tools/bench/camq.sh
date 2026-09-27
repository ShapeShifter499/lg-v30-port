#!/bin/sh
# camera quality pass: rotation property, then frames with the stock and the CCM tuning
W=${1:-1920}; H=${2:-1080}; N=${3:-30}
cd /tmp; rm -f camq-*.ppm
cam -c1 -p 2>/dev/null | grep -E 'Rotation|Location|Model' | head -3
timeout 60 cam -c1 --capture=$N -s width=$W,height=$H,pixelformat=ABGR8888 --file=/tmp/camq-stock-#.ppm >/tmp/camq-stock.log 2>&1; echo "stock rc=$?"
LIBCAMERA_SIMPLE_TUNING_FILE=/tmp/imx351-ccm.yaml timeout 60 cam -c1 --capture=$N -s width=$W,height=$H,pixelformat=ABGR8888 --file=/tmp/camq-ccm-#.ppm >/tmp/camq-ccm.log 2>&1; echo "ccm rc=$?"
grep -iE 'tuning|ccm|error' /tmp/camq-ccm.log | head -5
ls /tmp/camq-*.ppm | wc -l

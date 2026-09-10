#!/bin/bash
set -u
S=/tmp/claude-1002/-home-kumo02/10a89c2c-4210-4ed3-b3a7-7cab08028283/scratchpad/joan
cd ~/vibe-coding-projects/coding/linux-mainline-v30
# wait for the module build to finish
while pgrep -f "make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules" >/dev/null; do sleep 10; done
echo "=== build finished, tail:"; tail -3 "$S/modbuild.log"
grep -qiE "^make.*Error|Error [0-9]" "$S/modbuild.log" && echo "!!! BUILD ERRORS PRESENT"
STAGE=$S/modstage
rm -rf "$STAGE"; mkdir -p "$STAGE"
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules_install \
     INSTALL_MOD_PATH="$STAGE" INSTALL_MOD_STRIP=1 > "$S/modinstall.log" 2>&1
echo "=== installed:"; ls "$STAGE/lib/modules/"
echo "=== size:"; du -sh "$STAGE/lib/modules/"*
echo "=== key modules:"
find "$STAGE" -name "qcom_q6v5_pas.ko*" -o -name "apr.ko*" -o -name "snd-soc-wcd934x.ko*" | head
cd "$STAGE" && tar czf "$S/joan-modules.tgz" lib/modules/
echo "=== tarball:"; ls -lh "$S/joan-modules.tgz"

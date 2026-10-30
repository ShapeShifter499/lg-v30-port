#!/bin/sh
# Stage SMS files only. Do not start services or send messages.
set -eu
[ "$#" -eq 1 ] || { echo "Usage: $0 STAGING_ROOT" >&2; exit 2; }
root=$1
src=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
install -d -m 0755 "$root/opt/v30-sms" "$root/usr/local/sbin" "$root/etc/init.d"
for file in sms_core.py sms_bus.py smsd.py; do
    install -m 0755 "$src/$file" "$root/opt/v30-sms/$file"
done
install -m 0755 "$src/v30-sms" "$root/usr/local/sbin/v30-sms"
install -m 0755 "$src/v30-sms.init" "$root/etc/init.d/v30-sms"

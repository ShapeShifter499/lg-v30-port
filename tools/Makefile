# Static aarch64 helpers for joan bring-up.
#
#   make -C tools                 # msmprobe, msmsubmit -> tools/out/
#   make -C tools wdkill          # rebuild initramfs/root/bin/wdkill
#
# Everything is linked -static: the targets run from the bring-up
# initramfs or a bare pmOS shell with no matching libc.

CROSS_COMPILE ?= aarch64-linux-gnu-
CC            := $(CROSS_COMPILE)gcc
CFLAGS        ?= -O1 -Wall
LDFLAGS       += -static

OUT    := out
PROBES := $(OUT)/msmprobe $(OUT)/msmsubmit
WDKILL := ../initramfs/root/bin/wdkill

all: $(PROBES)

$(OUT)/%: %.c
	@mkdir -p $(OUT)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

# Replaces the tracked binary; commit it together with any wdkill.c change.
wdkill: $(WDKILL)
$(WDKILL): ../initramfs/src/wdkill.c
	$(CC) $(CFLAGS) $(LDFLAGS) -s -o $@ $<

clean:
	rm -rf $(OUT)

.PHONY: all wdkill clean

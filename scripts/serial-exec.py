#!/usr/bin/env python3
"""Safe ttyACM0 access for joan's pmOS initramfs debug shell.

Replaces the scratchpad-local serial-exec.py that kept getting lost when
/tmp was cleared (2026-07-19 handoff, and again 2026-08-15).

WHY THIS EXISTS: never attach a bare `cat`/`echo` to /dev/ttyACM0. The host
tty line discipline echoes what it reads back down the wire, which feeds the
phone's shell its own output and corrupts the session. This opens the port
raw (no echo, no canonical mode), drains stale bytes, then brackets the
command with sentinels so the caller can tell real output from banner noise.

USAGE
  sudo python3 serial-exec.py                    # passive read, 6s
  sudo python3 serial-exec.py 'cat /pmOS_init.log'
  sudo python3 serial-exec.py 'dmesg | tail -50' --timeout 20

  # read-only sanity check that the channel works at all:
  sudo python3 serial-exec.py --probe

EXIT
  0 output captured (sentinels seen)   2 timeout waiting for end sentinel
  3 port missing/busy                  4 probe failed
"""

import argparse
import os
import select
import sys
import termios
import time
import tty

DEV = "/dev/ttyACM0"
BEGIN = "___JOAN_BEGIN___"
END = "___JOAN_END___"


def open_raw(dev):
    try:
        fd = os.open(dev, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    except FileNotFoundError:
        print(f"serial-exec: {dev} not present -- gadget may have re-enumerated "
              f"without the ACM function (the pmOS rootfs drops it; only the "
              f"initramfs exposes ACM)", file=sys.stderr)
        raise SystemExit(3)
    except PermissionError:
        print(f"serial-exec: cannot open {dev} (try sudo)", file=sys.stderr)
        raise SystemExit(3)

    tty.setraw(fd)
    a = termios.tcgetattr(fd)
    a[3] &= ~(termios.ECHO | termios.ECHOE | termios.ECHOK
              | termios.ECHONL | termios.ICANON)
    a[1] &= ~termios.OPOST          # no output post-processing
    termios.tcsetattr(fd, termios.TCSANOW, a)
    termios.tcflush(fd, termios.TCIOFLUSH)   # drop stale banner bytes
    return fd


def drain(fd, seconds):
    end = time.time() + seconds
    buf = b""
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.2)
        if r:
            try:
                chunk = os.read(fd, 4096)
            except (BlockingIOError, OSError):
                continue
            if chunk:
                buf += chunk
                end = time.time() + 0.4     # extend while data still flowing
    return buf


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("command", nargs="?", default=None)
    ap.add_argument("--timeout", type=float, default=15.0)
    ap.add_argument("--dev", default=DEV)
    ap.add_argument("--probe", action="store_true",
                    help="positive-control the channel; writes only a newline")
    args = ap.parse_args()

    fd = open_raw(args.dev)
    try:
        if args.probe:
            os.write(fd, b"\n")
            out = drain(fd, 4)
            if out.strip():
                sys.stdout.write(out.decode("utf-8", "replace"))
                print("\nPROBE=OK (channel carries data)")
                return 0
            print("PROBE=SILENT -- a silent probe is NOT proof of a healthy "
                  "channel; confirm the phone is in the initramfs shell",
                  file=sys.stderr)
            return 4

        if args.command is None:
            sys.stdout.write(drain(fd, 6).decode("utf-8", "replace"))
            return 0

        # SPLIT SENTINELS. The phone's shell echoes the command line back, so
        # a plain `echo ___JOAN_BEGIN___` puts the marker on the wire TWICE:
        # once in the echoed command, once as real output. Searching then
        # locks onto the echo and returns the command text instead of the
        # result. Writing the marker split by an empty-string concatenation
        # means the echoed line shows `___JOAN_B""EGIN___` while the executed
        # echo emits the joined `___JOAN_BEGIN___` -- so the literal we search
        # for appears only in genuine output.
        b_split = BEGIN[:9] + '""' + BEGIN[9:]
        e_split = END[:9] + '""' + END[9:]
        script = f"echo {b_split}; {args.command}; echo {e_split}\n"
        os.write(fd, script.encode())

        deadline = time.time() + args.timeout
        buf = b""
        while time.time() < deadline:
            r, _, _ = select.select([fd], [], [], 0.3)
            if r:
                try:
                    buf += os.read(fd, 4096)
                except (BlockingIOError, OSError):
                    pass
            if END.encode() in buf:
                break
        else:
            sys.stdout.write(buf.decode("utf-8", "replace"))
            print(f"\nserial-exec: timeout after {args.timeout}s waiting for "
                  f"end sentinel", file=sys.stderr)
            return 2

        text = buf.decode("utf-8", "replace")
        # Take what is between the LAST begin and the following end, so a
        # re-echoed command line does not win over the real output.
        start = text.rfind(BEGIN)
        body = text[start + len(BEGIN):] if start >= 0 else text
        stop = body.find(END)
        if stop >= 0:
            body = body[:stop]
        sys.stdout.write(body.lstrip("\r\n"))
        return 0
    finally:
        os.close(fd)


if __name__ == "__main__":
    raise SystemExit(main())

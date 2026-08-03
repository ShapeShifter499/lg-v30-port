# joan: getting a working, seat-attached Phosh session on postmarketOS

Assisted-by: Claude-Code:claude-opus-5
Date: 2026-07-27

Everything here is device-side configuration on the SD rootfs, not kernel work.
It is written down because every step failed for a non-obvious reason first.

## Why a seat matters: the brightness slider

GNOME sets panel brightness through logind's `SetBrightness`, and logind
refuses that call for a session with no seat. A session started by hand over
ssh is `Seat=` empty, `Remote=yes`, `Type=tty`, so the slider silently does
nothing no matter how good the backlight driver is. Adding a udev rule to make
`/sys/class/backlight/*/brightness` group-writable does *not* help either:
gsd-power uses logind whenever a logind proxy exists and never falls back.

The fix is to have greetd start the session on a real VT, so it lands on
`seat0`. Verified working:

    session 1: Name=user Seat=seat0 Type=tty Active=yes
    busctl call ... SetBrightness ssu backlight c994000.dsi.0 180  -> rc=0
    /sys/class/backlight/c994000.dsi.0/brightness: 255 -> 180

## The four traps, in the order they bite

1. **The greetd service does not read `/etc/greetd/config.toml`.**
   `/etc/conf.d/greetd` sets `cfgfile="/etc/phrog/greetd-config.toml"`. Editing
   the former achieves nothing; the phrog file ships with `[initial_session]`
   commented out, so you get the greeter instead of autologin.

2. **`[initial_session]` only runs when `/run/greetd.run` is absent.**
   That marker is greetd's "already started once this boot" flag. Any manual
   `greetd` run during testing creates it and every later start silently falls
   through to `default_session`. Harmless at real boot (fresh tmpfs), very
   confusing when testing by hand -- `rm -f /run/greetd.run` first.

3. **greetd does not propagate the PAM environment to the session child.**
   pam_elogind creates `/run/user/10000`, but `XDG_RUNTIME_DIR` never reaches
   phoc, which dies with "XDG_RUNTIME_DIR is invalid or not set". Set it
   explicitly in the session command.

4. **Nothing referenced `pam_elogind`.** `/etc/pam.d/greetd` included
   `base-auth`/`base-account`/`base-session`, none of which exist on this
   image. Without pam_elogind no session is registered with elogind at all.

## Working configuration

`/etc/phrog/greetd-config.toml`:

    [terminal]
    vt = 7

    [default_session]
    command = "/usr/libexec/phrog-greetd-session"
    user = "greetd"

    [initial_session]
    command = "env XDG_RUNTIME_DIR=/run/user/10000 WLR_RENDERER=gles2 phosh-session"
    user = "user"

`/etc/pam.d/greetd` -- a self-contained stack ending in
`session optional pam_elogind.so`.

`/etc/udev/rules.d/90-backlight.rules` -- makes the brightness attribute
group-writable. Not sufficient on its own (see above) but correct to have.

`rc-update add greetd default`.

`WLR_RENDERER=gles2` is set explicitly because `/etc/environment` still pins
`WLR_RENDERER=pixman` from the software-rendering era. That line can be dropped
now that the GPU works; it is left in place so a failed GPU boot still has a
fallback.

Backups of every file replaced are alongside the originals as `*.bak-<stamp>`.

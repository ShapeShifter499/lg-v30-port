# phosh/lockscreen no-start — ROOT-CAUSED + FIXED — 2026-08-05

## Owner ask
"Let's make sure phosh and lockscreen is working" (after G6-OC3-RX
reported a spinning plymouth with no phosh; the GPU corner PASS was
unaffected — this is the userspace graphical stack).

## Root cause (machine-evidenced)

The e2fsck repair that fixed the boot-wedge saga (see
joan-boot-wedge-gpu-oc-2026-08.md) ORPHANED the user's home
directory into /lost+found:

- `/home/user` was GONE; `/etc/passwd` still mapped user -> /home/user
- SSH login: "Could not chdir to home directory /home/user"
- Mesa render loop: "Failed to create /home/user for shader cache"
- phosh started (~t=59s), hit its first home/config access, the
  session tore down: Xwayland crashed (26 MB core dump in /lost+found
  #3860, "Xwayland :0 -rootless"), pulseaudio reported "X11 I/O
  error", greetd logged "Will stop /usr/sbin/greetd", and the DPU
  logged "no encoder found for crtc 0" during teardown
- Result: plymouth spinner forever — greetd's session died, nothing
  restarted it, no input path (touch flooding 0-0049)

Recovered fragments identified:
- /lost+found/#115971 = old .config (dconf, gnome-session, gtk-3.0, ibus, pulse)
- /lost+found/#115969 = old .cache (mesa_shader_cache, gnome-software)
- /lost+found/#103 = old .ssh (authorized_keys)
- /lost+found/#125325 = old .local (share + state)
- /lost+found/#3860 = Xwayland core dump (the crash)

## Fix (owner-authorized persistent rootfs change, applied in-session)

1. mkdir /home/user; chown 10000:10000
2. Restore fragments: .config, .cache, .ssh, .local (cp -a + chown -R)
3. rc-service greetd restart  -> new session (phrog greeter first,
   then auto-login -> full phosh session)

## Verification

- Machine: phosh RUNNING (pid alive), phoc + gnome-session +
  phosh-osk-stevi all up; dconf DB present in /home/user/.config/
  dconf/; home ownership correct; NO new kernel errors after restart
  (the "no encoder" lines are all from the old session teardown)
- Owner-visible: "looks good here" — the lockscreen/greeter renders
  on glass (2026-08-05)

## Evidence hashes

- phosh-check-ramboot-live.log: 4ac86aa19e0b3d9a65118008bb47831d87d3eb219cde2eb4c5369fd607b939ee
- phosh-check-diagnostic.log: 64f5b070e6ab7a639b460a7d216e74fa24732b5b36bbdcf8aaa91a318e299559

## Lesson (skill)

After ANY e2fsck repair on a device rootfs, check /lost+found for
orphaned user homes BEFORE declaring userspace healthy: `ls /home/`
vs `/etc/passwd`, look for `#<inode>` dirs owned by the user, restore
with cp -a + chown, restart the display manager. Also: a greetd
restart lands in the phrog greeter session first; auto-login then
spawns the full `--session=phosh` shell.

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-08-05

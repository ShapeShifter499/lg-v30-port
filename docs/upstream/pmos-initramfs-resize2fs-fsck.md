# Draft: postmarketOS merge request — initramfs ext4 resize after pmbootstrap images

Status: **draft, not submitted** (needs Lance's go-ahead; it is a public post).
Target: gitlab.postmarketos.org/postmarketOS/pmaports, `main/postmarketos-initramfs`.
Local commit: pmaports-lge-joan `61cba4999e`.

## Title

main/postmarketos-initramfs: check ext4 fully when resize2fs asks for it

## Description

Since 8e2ce06af5 ("don't resize ext4 with fsck errors", MR 5844),
`resize_root_filesystem` calls plain `resize2fs` after the `e2fsck -p` in
`check_filesystem`. resize2fs will not work offline on a file system that
has been mounted since its last full check (`s_lastcheck < s_mtime`). Every
image pmbootstrap builds is in that state, because the rootfs is copied in
through a mount after mkfs. `e2fsck -p` leaves a clean file system alone
without moving `s_lastcheck`, so the first boot prints

    resize2fs 1.47.4 (6-Mar-2025)
    Please run 'e2fsck -f /dev/mmcblk0p2' first.

and the root partition is grown but the file system keeps its install
size. On an LG V30 (lge-joan, microSD, pmbootstrap 3.11.1, edge
2026-09-26) that was 2.4 GB used 90 % on a 182.9 GB partition.

Reproducer (any Linux host, e2fsprogs 1.47.4):

    truncate -s 200M t.img; mkfs.ext4 -q -F t.img; sleep 2
    sudo mount -o loop t.img mnt && sudo touch mnt/x && sudo umount mnt
    truncate -s 400M t.img
    e2fsck -p t.img        # "clean", last checked stays before the mount
    resize2fs t.img        # "Please run 'e2fsck -f t.img' first."

The change: when resize2fs fails, run `e2fsck -f -p` and try once more.
Preen mode still refuses anything that needs manual repair, so a file
system with real errors is not resized, which was the intent of MR 5844.
The full check only runs on a boot where the file system was actually
smaller than its partition and resize2fs refused. After that, resize2fs has
nothing to do and the extra step never runs.

Tested: the reproducer above goes from refusal to a grown file system;
`abuild check` 6/6.

```diff
 		ext4)
 			echo "Resize 'ext4' root filesystem ($partition)"
 			modprobe ext4
-			resize2fs "$partition"
+			if ! resize2fs "$partition"; then
+				# resize2fs refuses a file system that was mounted
+				# after its last full check, and every image
+				# pmbootstrap builds is (it copies the rootfs in after
+				# mkfs); e2fsck -p above skips a clean one. Check it
+				# fully -- preen mode still stops on real errors --
+				# and try once more.
+				echo "Check 'ext4' root filesystem before resize ($partition)"
+				e2fsck -f -p "$partition" && resize2fs "$partition"
+			fi
 			;;
```

#!/sbin/sh

WORK="/cache/decrypt_work"
PASSFILE="$1"

if [ -z "$PASSFILE" ]; then
  echo "Usage: sh $0 /cache/decrypt_work/passwords_file.txt"
  exit 1
fi

case "$PASSFILE" in
  /*) ;;
  *) PASSFILE="$WORK/$PASSFILE" ;;
esac

if [ ! -f "$PASSFILE" ]; then
  echo "[ERROR] password file not found: $PASSFILE"
  exit 1
fi

echo "[*] Using password file: $PASSFILE"

echo "[*] Mounting /system..."
mkdir -p /system
mount | grep " /system " >/dev/null || mount -o ro -t ext4 /dev/block/by-name/SYSTEM /system 2>/dev/null || mount -o ro -t ext4 /dev/block/mmcblk0p21 /system

if [ ! -x /system/bin/vdc ]; then
  echo "[ERROR] /system/bin/vdc missing. /system mount failed."
  exit 1
fi

echo "[*] Preparing /vendor and Samsung paths..."
setenforce 0 2>/dev/null || true

mkdir -p /dev/socket
mkdir -p /dev/.secure_storage
mkdir -p /data/system/secure_storage
mkdir -p /data/misc/vold
mkdir -p /data/unencrypted
mkdir -p /cache/recovery

umount /vendor 2>/dev/null || true
rm -rf /vendor
ln -s /system/vendor /vendor

echo "[*] Writing fstab aliases..."
printf "%s\n%s\n%s\n%s\n" \
"/dev/block/mmcblk0p21 /system ext4 ro,errors=panic,noload wait" \
"/dev/block/mmcblk0p22 /cache ext4 nosuid,nodev,noatime,noauto_da_alloc,discard,journal_async_commit,errors=panic wait,check" \
"/dev/block/mmcblk0p25 /data ext4 nosuid,nodev,noatime,noauto_da_alloc,discard,journal_async_commit,errors=panic wait,check,forceencrypt=footer" \
"/dev/block/mmcblk0p3 /efs ext4 nosuid,nodev,noatime,noauto_da_alloc,discard,journal_async_commit,errors=panic wait,check" \
> /fstab

cp /fstab /fstab.
cp /fstab /fstab.samsungexynos7870
cp /fstab /fstab.exynos7870
cp /fstab /fstab.on7xelte

echo "[*] Installing runtime binaries into /tmp..."
cp "$WORK/vold_patched" /tmp/vold_patched
cp "$WORK/run_vold_patched_with_sockets" /tmp/run_vold_patched_with_sockets
chmod 755 /tmp/vold_patched /tmp/run_vold_patched_with_sockets

echo "[*] Restarting patched Samsung vold stack..."
killall vold 2>/dev/null || true
killall vold_patched 2>/dev/null || true
killall secure_storage_daemon 2>/dev/null || true
sleep 1

rm -f /dev/.secure_storage/ssd_socket
rm -f /dev/socket/vold /dev/socket/cryptd /dev/socket/frigate /dev/socket/epm /dev/socket/ppm /dev/socket/dir_enc_report

export LD_LIBRARY_PATH=/vendor/lib:/system/vendor/lib:/system/lib:/sbin
export PATH=/system/bin:/sbin:/bin
export ANDROID_ROOT=/system
export ANDROID_DATA=/data

/system/bin/secure_storage_daemon >"$WORK/secure_storage_daemon.out" 2>"$WORK/secure_storage_daemon.err" &
sleep 2

/tmp/run_vold_patched_with_sockets >"$WORK/run_vold_patched_wrapper.out" 2>"$WORK/run_vold_patched_wrapper.err" &
sleep 3

echo "[*] Status:"
ps -A | grep -Ei "vold|secure_storage" || true
ls -l /dev/socket/cryptd /dev/.secure_storage/ssd_socket 2>/dev/null || true

if [ ! -S /dev/socket/cryptd ]; then
  echo "[ERROR] cryptd socket missing. Patched vold did not start correctly."
  echo "[*] Wrapper log:"
  cat "$WORK/run_vold_patched_wrapper.err" "$WORK/run_vold_patched_wrapper.out" 2>/dev/null | tail -80
  exit 1
fi

echo "[*] Starting local password test."
echo "[*] If success happens, FOUND_PASSWORD will be saved to:"
echo "    $WORK/FOUND_PASSWORD.txt"
echo

SHOW_CANDIDATE="${SHOW_CANDIDATE:-0}" \
MAX_TRIES="${MAX_TRIES:-999999}" \
CHECK_DM_EVERY="${CHECK_DM_EVERY:-250}" \
sh "$WORK/device_try_passwords.sh" "$PASSFILE"

RC="$?"

if [ -f /tmp/FOUND_PASSWORD.txt ]; then
  cp /tmp/FOUND_PASSWORD.txt "$WORK/FOUND_PASSWORD.txt"
  chmod 600 "$WORK/FOUND_PASSWORD.txt"
  echo "[*] Copied found password to $WORK/FOUND_PASSWORD.txt"
fi

exit "$RC"

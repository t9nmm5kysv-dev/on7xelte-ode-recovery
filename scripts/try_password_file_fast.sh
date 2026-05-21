#!/usr/bin/env bash
set -u

PASSFILE="${1:-/home/zyxblvxb/Desktop/passwords.txt}"
MAX_TRIES="${MAX_TRIES:-5000}"
CHECK_DM_EVERY="${CHECK_DM_EVERY:-25}"
SHOW_CANDIDATE="${SHOW_CANDIDATE:-1}"

if [ ! -f "$PASSFILE" ]; then
  echo "[ERROR] Password file not found: $PASSFILE"
  exit 1
fi

now_float() {
  python3 - <<'PY'
import time
print(time.time())
PY
}

stats() {
  python3 - "$@" <<'PY'
import sys
start=float(sys.argv[1])
now=float(sys.argv[2])
attempt=int(sys.argv[3])
planned=int(sys.argv[4])
elapsed=now-start
avg=elapsed/attempt if attempt else 0
remaining=max(planned-attempt,0)
eta=avg*remaining
def fmt(s):
    h=int(s//3600); m=int((s%3600)//60); sec=int(s%60)
    return f"{h:02d}:{m:02d}:{sec:02d}"
print(f"avg={avg:.2f}s elapsed={fmt(elapsed)} eta={fmt(eta)} remaining={remaining}")
PY
}

TOTAL=$(awk '
{
  sub(/\r$/, "")
  if ($0 == "") next
  if ($0 ~ /^#/) next
  if (!seen[$0]++) count++
}
END { print count+0 }
' "$PASSFILE")

if [ "$TOTAL" -eq 0 ]; then
  echo "[ERROR] No usable candidates."
  exit 1
fi

if [ "$MAX_TRIES" -gt "$TOTAL" ]; then
  PLANNED="$TOTAL"
else
  PLANNED="$MAX_TRIES"
fi

echo "[*] Fast mode"
echo "[*] File: $PASSFILE"
echo "[*] Usable candidates: $TOTAL"
echo "[*] Planned attempts: $PLANNED"
echo "[*] dm check every: $CHECK_DM_EVERY attempts"
echo

if ! adb shell -n 'ps -A | grep -q "[v]old_patched"' >/dev/null 2>&1; then
  echo "[ERROR] vold_patched is not running. Run setup first."
  exit 1
fi

if ! adb shell -n 'ls /dev/socket/cryptd >/dev/null 2>&1' >/dev/null 2>&1; then
  echo "[ERROR] cryptd socket missing. Run setup first."
  exit 1
fi

attempt=0
seen_tmp="$(mktemp)"
START="$(now_float)"
trap 'rm -f "$seen_tmp"; printf "\n"' EXIT

while IFS= read -r candidate <&3 || [ -n "${candidate:-}" ]; do
  candidate="${candidate%$'\r'}"

  [ -z "$candidate" ] && continue
  case "$candidate" in
    \#*) continue ;;
  esac

  h="$(printf '%s' "$candidate" | sha256sum | awk '{print $1}')"
  if grep -qx "$h" "$seen_tmp"; then
    continue
  fi
  echo "$h" >> "$seen_tmp"

  attempt=$((attempt + 1))
  if [ "$attempt" -gt "$MAX_TRIES" ]; then
    printf '\n[STOP] Hit MAX_TRIES=%s\n' "$MAX_TRIES"
    exit 2
  fi

  cand="$candidate"
  qpass="$(printf '%s' "$cand" | python3 -c 'import shlex,sys; print(shlex.quote(sys.stdin.read()))')"

  out="$(adb shell -n "
export LD_LIBRARY_PATH=/vendor/lib:/system/vendor/lib:/system/lib:/sbin
export PATH=/system/bin:/sbin:/bin
/system/bin/vdc --wait cryptfs checkpw $qpass
" 2>/dev/null | tr -d '\r')"

  now="$(now_float)"
  st="$(stats "$START" "$now" "$attempt" "$PLANNED")"

  if [ "$SHOW_CANDIDATE" = "1" ]; then
    printf '\r\033[K[RUNNING] attempt=%s/%s %s candidate=%s' "$attempt" "$PLANNED" "$st" "$cand"
  else
    printf '\r\033[K[RUNNING] attempt=%s/%s %s candidate hidden' "$attempt" "$PLANNED" "$st"
  fi

  # Check dm periodically, not every attempt.
  if [ $((attempt % CHECK_DM_EVERY)) -eq 0 ]; then
    dm="$(adb shell -n 'ls /dev/block/dm-* 2>/dev/null' | tr -d '\r')"
    if [ -n "$dm" ]; then
      printf '\n[SUCCESS] dm device appeared.\n'
      echo "[FOUND_CANDIDATE] $cand"
      printf '%s\n' "$cand" > /home/zyxblvxb/Desktop/FOUND_PASSWORD.txt
      chmod 600 /home/zyxblvxb/Desktop/FOUND_PASSWORD.txt

      adb shell -n 'mkdir -p /data'
      adb shell -n 'mount -t ext4 -o ro /dev/block/dm-0 /data 2>&1'
      adb shell -n 'ls -la /data/media/0 2>&1'

      echo
      echo "Pull with:"
      echo "mkdir -p /home/zyxblvxb/Desktop/phone_recovered"
      echo "adb pull /data/media/0 /home/zyxblvxb/Desktop/phone_recovered/"
      exit 0
    fi
  fi

  # If vdc response is weird, inspect logs.
  case "$out" in
    200\ * ) ;;
    * )
      printf '\n[UNKNOWN] vdc output: %s\n' "$out"
      adb shell -n 'logcat -d | grep -iE "CryptfsODE|Password did not match|Decryption operation succeeded|decrypt master key|dm-|keymaster|cryptfs|failed|success|test mount" | tail -80'
      ;;
  esac

done 3< "$PASSFILE"

printf '\n[DONE] End of file. No success.\n'
END="$(now_float)"
python3 - "$START" "$END" <<'PY'
import sys
s=float(sys.argv[2])-float(sys.argv[1])
h=int(s//3600); m=int((s%3600)//60); sec=int(s%60)
print(f"[TIME] Total runtime: {h:02d}:{m:02d}:{sec:02d}")
PY
exit 3

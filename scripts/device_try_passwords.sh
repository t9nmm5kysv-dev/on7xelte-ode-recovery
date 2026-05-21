#!/sbin/sh

PASSFILE="${1:-/cache/decrypt_work/passwords_seqrep_all.txt}"
MAX_TRIES="${MAX_TRIES:-999999}"
PLANNED_TRIES="${PLANNED_TRIES:-419152}"
CHECK_DM_EVERY="${CHECK_DM_EVERY:-250}"
STATUS_EVERY="${STATUS_EVERY:-100}"
SHOW_CANDIDATE="${SHOW_CANDIDATE:-0}"

if [ ! -f "$PASSFILE" ]; then
  echo "[ERROR] missing password file: $PASSFILE"
  exit 1
fi

uptime_s() {
  read up rest < /proc/uptime
  echo "${up%%.*}"
}

fmt_hms() {
  total="$1"
  [ "$total" -lt 0 ] && total=0
  h=$((total / 3600))
  m=$(((total % 3600) / 60))
  s=$((total % 60))
  printf "%02dh %02dm %02ds" "$h" "$m" "$s"
}

echo "[*] Device-side local mode"
echo "[*] File: $PASSFILE"
echo "[*] Planned attempts: $PLANNED_TRIES"
echo "[*] CHECK_DM_EVERY=$CHECK_DM_EVERY"
echo "[*] STATUS_EVERY=$STATUS_EVERY"
echo

start_s="$(uptime_s)"
attempt=0
failed=0

while IFS= read -r candidate || [ -n "$candidate" ]; do
  candidate="${candidate%
}"

  [ -z "$candidate" ] && continue
  case "$candidate" in \#*) continue ;; esac

  attempt=$((attempt + 1))

  if [ "$attempt" -gt "$MAX_TRIES" ]; then
    echo
    echo "[STOP] Hit MAX_TRIES=$MAX_TRIES"
    exit 2
  fi

  before_s="$(uptime_s)"

  env LD_LIBRARY_PATH=/vendor/lib:/system/vendor/lib:/system/lib:/sbin \
      PATH=/system/bin:/sbin:/bin \
      /system/bin/vdc --wait cryptfs checkpw "$candidate" >/tmp/vdc_try.out 2>/tmp/vdc_try.err

  after_s="$(uptime_s)"
  failed=$attempt

  elapsed_s=$((after_s - start_s))
  last_s=$((after_s - before_s))
  [ "$elapsed_s" -lt 0 ] && elapsed_s=0
  [ "$last_s" -lt 0 ] && last_s=0

  remaining=$((PLANNED_TRIES - attempt))
  [ "$remaining" -lt 0 ] && remaining=0

  # ETA based on integer math only:
  # eta = elapsed * remaining / attempt
  if [ "$attempt" -gt 0 ]; then
    eta_s=$((elapsed_s * remaining / attempt))
  else
    eta_s=0
  fi

  if [ $((attempt % STATUS_EVERY)) -eq 0 ]; then
    elapsed_text="$(fmt_hms "$elapsed_s")"
    eta_text="$(fmt_hms "$eta_s")"

    if [ "$SHOW_CANDIDATE" = "1" ]; then
      echo "[RUNNING] attempt=$attempt/$PLANNED_TRIES failed=$failed last=${last_s}s elapsed=$elapsed_text eta=$eta_text remaining=$remaining candidate=$candidate"
    else
      echo "[RUNNING] attempt=$attempt/$PLANNED_TRIES failed=$failed last=${last_s}s elapsed=$elapsed_text eta=$eta_text remaining=$remaining"
    fi
  fi

  if [ $((attempt % CHECK_DM_EVERY)) -eq 0 ]; then
    if ls /dev/block/dm-* >/dev/null 2>&1; then
      echo
      echo "[SUCCESS] dm device appeared"
      echo "[FOUND_CANDIDATE] $candidate"
      echo "$candidate" > /tmp/FOUND_PASSWORD.txt
      echo "$candidate" > /cache/decrypt_work/FOUND_PASSWORD.txt
      chmod 600 /tmp/FOUND_PASSWORD.txt /cache/decrypt_work/FOUND_PASSWORD.txt 2>/dev/null

      mkdir -p /data
      mount -t ext4 -o ro /dev/block/dm-0 /data 2>&1
      ls -la /data/media/0 2>&1
      exit 0
    fi
  fi

done < "$PASSFILE"

echo
echo "[DONE] End of file. No success."
exit 3

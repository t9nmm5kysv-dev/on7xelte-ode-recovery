#!/usr/bin/env bash
set -u

PASSFILE="${1:-/home/zyxblvxb/Desktop/passwords.txt}"
MAX_TRIES="${MAX_TRIES:-5000}"
DELAY_SECONDS="${DELAY_SECONDS:-0}"
SHOW_CANDIDATE="${SHOW_CANDIDATE:-1}"

# Colors. Disable with NO_COLOR=1.
if [ -t 1 ] && [ "${NO_COLOR:-0}" != "1" ]; then
  BOLD="$(printf '\033[1m')"
  DIM="$(printf '\033[2m')"
  RED="$(printf '\033[31m')"
  GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"
  BLUE="$(printf '\033[34m')"
  MAGENTA="$(printf '\033[35m')"
  CYAN="$(printf '\033[36m')"
  RESET="$(printf '\033[0m')"
else
  BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""; RESET=""
fi

if [ ! -f "$PASSFILE" ]; then
  echo "${RED}[ERROR]${RESET} Password file not found: $PASSFILE"
  exit 1
fi

now_float() {
  python3 - <<'PY'
import time
print(time.time())
PY
}

make_stats() {
  python3 - "$@" <<'PY'
import sys

start = float(sys.argv[1])
attempt_start = float(sys.argv[2])
attempt_end = float(sys.argv[3])
attempt = int(sys.argv[4])
planned = int(sys.argv[5])

last = attempt_end - attempt_start
elapsed = attempt_end - start
avg = elapsed / attempt if attempt else 0
remaining = max(planned - attempt, 0)
eta = avg * remaining

def fmt(s):
    if s < 0:
        s = 0
    h = int(s // 3600)
    m = int((s % 3600) // 60)
    sec = int(s % 60)
    return f"{h:02d}:{m:02d}:{sec:02d}"

print(f"last={last:.2f}s avg={avg:.2f}s elapsed={fmt(elapsed)} eta={fmt(eta)} remaining={remaining}")
PY
}

TOTAL_LINES=$(wc -l < "$PASSFILE" | tr -d ' ')
USABLE_COUNT=$(awk '
{
  sub(/\r$/, "")
  if ($0 == "") next
  if ($0 ~ /^#/) next
  if (!seen[$0]++) count++
}
END { print count+0 }
' "$PASSFILE")

if [ "$USABLE_COUNT" -eq 0 ]; then
  echo "${RED}[ERROR]${RESET} No usable candidates."
  exit 1
fi

if [ "$MAX_TRIES" -gt "$USABLE_COUNT" ]; then
  PLANNED_TRIES="$USABLE_COUNT"
else
  PLANNED_TRIES="$MAX_TRIES"
fi

echo "${BOLD}${CYAN}[*] Using password file:${RESET} $PASSFILE"
echo "${BOLD}${CYAN}[*] Physical lines:${RESET} $TOTAL_LINES"
echo "${BOLD}${CYAN}[*] Usable unique candidates:${RESET} $USABLE_COUNT"
echo "${BOLD}${CYAN}[*] Planned attempts this run:${RESET} $PLANNED_TRIES"
echo "${BOLD}${CYAN}[*] Delay between attempts:${RESET} ${DELAY_SECONDS}s"
echo "${BOLD}${CYAN}[*] Mode:${RESET} fixed colorful two-line status"
echo

if ! adb shell -n 'ps -A | grep -q "[v]old_patched"' >/dev/null 2>&1; then
  echo "${RED}[ERROR]${RESET} vold_patched is not running. Run setup first."
  exit 1
fi

if ! adb shell -n 'ls -l /dev/socket/cryptd >/dev/null 2>&1' >/dev/null 2>&1; then
  echo "${RED}[ERROR]${RESET} /dev/socket/cryptd missing. Run setup first."
  exit 1
fi

echo
echo

status_row="$(tput lines 2>/dev/null || echo 0)"
status_row=$((status_row - 2))
if [ "$status_row" -lt 1 ]; then
  status_row=1
fi

shorten() {
  local text="$1"
  local max="${2:-80}"
  if [ "${#text}" -gt "$max" ]; then
    printf "%s..." "${text:0:$((max - 3))}"
  else
    printf "%s" "$text"
  fi
}

draw_status() {
  local line1="$1"
  local line2="$2"

  printf '\0337'
  tput cup "$status_row" 0 2>/dev/null || true
  printf '\033[2K%s' "$line1"
  tput cup "$((status_row + 1))" 0 2>/dev/null || true
  printf '\033[2K%s' "$line2"
  printf '\0338'
}

attempt=0
failed=0
seen_tmp="$(mktemp)"
START_TIME="$(now_float)"
LAST_STATS="last=-- avg=-- elapsed=00:00:00 eta=-- remaining=$PLANNED_TRIES"

cleanup() {
  rm -f "$seen_tmp"
  tput cnorm 2>/dev/null || true
  printf '\n'
}
trap cleanup EXIT

tput civis 2>/dev/null || true

while IFS= read -r candidate <&3 || [ -n "${candidate:-}" ]; do
  candidate="${candidate%$'\r'}"

  [ -z "$candidate" ] && continue
  case "$candidate" in
    \#*) continue ;;
  esac

  hash="$(printf '%s' "$candidate" | sha256sum | awk '{print $1}')"
  if grep -qx "$hash" "$seen_tmp"; then
    continue
  fi
  echo "$hash" >> "$seen_tmp"

  attempt=$((attempt + 1))

  if [ "$attempt" -gt "$MAX_TRIES" ]; then
    tput cnorm 2>/dev/null || true
    printf '\n%s[STOP]%s Hit MAX_TRIES=%s. Not continuing.\n' "$YELLOW" "$RESET" "$MAX_TRIES"
    exit 2
  fi

  candidate_original="$candidate"
  ATTEMPT_START="$(now_float)"

  if [ "$SHOW_CANDIDATE" = "1" ]; then
    CAND_SHORT="$(shorten "$candidate_original" 70)"
    draw_status "${CYAN}[RUNNING]${RESET} ${BOLD}attempt=$attempt/$PLANNED_TRIES${RESET} failed=$failed ${YELLOW}$LAST_STATS${RESET}" "${BLUE}candidate=${RESET}$CAND_SHORT"
  else
    draw_status "${CYAN}[RUNNING]${RESET} ${BOLD}attempt=$attempt/$PLANNED_TRIES${RESET} failed=$failed ${YELLOW}$LAST_STATS${RESET}" "${DIM}candidate hidden${RESET}"
  fi

  QPASS="$(printf '%s' "$candidate_original" | python3 -c 'import shlex,sys; print(shlex.quote(sys.stdin.read()))')"
  candidate=""

  adb shell -n 'logcat -c' >/dev/null 2>&1

  adb shell -n "
export LD_LIBRARY_PATH=/vendor/lib:/system/vendor/lib:/system/lib:/sbin
export PATH=/system/bin:/sbin:/bin
/system/bin/vdc --wait cryptfs checkpw $QPASS
" >/tmp/try_decrypt_vdc.out 2>/tmp/try_decrypt_vdc.err

  QPASS=""

  ATTEMPT_END="$(now_float)"
  STATS="$(make_stats "$START_TIME" "$ATTEMPT_START" "$ATTEMPT_END" "$attempt" "$PLANNED_TRIES")"
  LAST_STATS="$STATS"

  DM="$(adb shell -n 'ls /dev/block/dm-* 2>/dev/null' | tr -d '\r')"
  LOG="$(adb shell -n 'logcat -d | grep -iE "CryptfsODE|Password did not match|Decryption operation succeeded|decrypt master key|dm-|keymaster|cryptfs|failed|success|test mount" | tail -80' 2>/dev/null | tr -d '\r')"

  if [ -n "$DM" ] || echo "$LOG" | grep -qi "Decryption operation succeeded"; then
    tput cnorm 2>/dev/null || true
    printf '\n%s[SUCCESS]%s Candidate worked.\n' "$GREEN" "$RESET"
    echo "${GREEN}[FOUND_CANDIDATE]${RESET} $candidate_original"
    printf '%s\n' "$candidate_original" > /home/zyxblvxb/Desktop/FOUND_PASSWORD.txt
    chmod 600 /home/zyxblvxb/Desktop/FOUND_PASSWORD.txt

    echo "${CYAN}[*] dm device:${RESET}"
    adb shell -n 'ls -l /dev/block/dm-* /dev/mapper 2>/dev/null'

    echo "${CYAN}[*] Trying read-only mount...${RESET}"
    adb shell -n 'mkdir -p /data'
    adb shell -n 'mount -t ext4 -o ro /dev/block/dm-0 /data 2>&1'
    adb shell -n 'ls -la /data/media/0 2>&1'

    echo
    echo "${CYAN}[*] Pull with:${RESET}"
    echo "mkdir -p /home/zyxblvxb/Desktop/phone_recovered"
    echo "adb pull /data/media/0 /home/zyxblvxb/Desktop/phone_recovered/"
    exit 0
  fi

  if echo "$LOG" | grep -qi "Password did not match"; then
    failed=$((failed + 1))
    STATUS="${RED}[FAILED]${RESET}"
  else
    STATUS="${YELLOW}[UNKNOWN]${RESET}"
  fi

  if [ "$SHOW_CANDIDATE" = "1" ]; then
    CAND_SHORT="$(shorten "$candidate_original" 70)"
    draw_status "$STATUS ${BOLD}attempt=$attempt/$PLANNED_TRIES${RESET} failed=$failed ${YELLOW}$STATS${RESET}" "${BLUE}candidate=${RESET}$CAND_SHORT"
  else
    draw_status "$STATUS ${BOLD}attempt=$attempt/$PLANNED_TRIES${RESET} failed=$failed ${YELLOW}$STATS${RESET}" "${DIM}candidate hidden${RESET}"
  fi

  candidate_original=""

  if [ "$DELAY_SECONDS" != "0" ]; then
    sleep "$DELAY_SECONDS"
  fi

done 3< "$PASSFILE"

TOTAL_END="$(now_float)"
TOTAL="$(python3 - "$START_TIME" "$TOTAL_END" <<'PY'
import sys
s = float(sys.argv[2]) - float(sys.argv[1])
h = int(s // 3600)
m = int((s % 3600) // 60)
sec = int(s % 60)
print(f"{h:02d}:{m:02d}:{sec:02d}")
PY
)"

tput cnorm 2>/dev/null || true
printf '\n%s[DONE]%s Reached end of candidate file. No success.\n' "$YELLOW" "$RESET"
echo "${CYAN}[TIME]${RESET} Total runtime: $TOTAL"
exit 3

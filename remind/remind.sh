#!/bin/bash
# remind.sh - macOS 알림 타이머 (Claude Code skill용)
# Usage: remind.sh <when> [message]

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: /remind <when> [message]

  Relative:  30s, 5m, 2h, 1h30m, 1h30m15s
  Absolute:  17:00, 5pm, 9:30am

Examples:
  /remind 5m 회의 시작
  /remind 17:00 퇴근 준비
  /remind 2h30m 빨래
USAGE
  exit 1
}

[[ $# -lt 1 ]] && usage

format_duration() {
  local s=$1
  local parts=()
  if [[ $s -ge 3600 ]]; then
    parts+=("$((s / 3600))h")
    s=$((s % 3600))
  fi
  if [[ $s -ge 60 ]]; then
    parts+=("$((s / 60))m")
    s=$((s % 60))
  fi
  if [[ $s -gt 0 || ${#parts[@]} -eq 0 ]]; then
    parts+=("${s}s")
  fi
  echo "${parts[*]}"
}

parse_relative() {
  local input="$1"
  local total=0

  if [[ "$input" =~ ^[0-9]+$ ]]; then
    echo "$input"
    return 0
  fi

  local remaining="$input"
  local matched=false

  if [[ "$remaining" =~ ^([0-9]+)h ]]; then
    total=$((total + ${BASH_REMATCH[1]} * 3600))
    remaining="${remaining#*h}"
    matched=true
  fi
  if [[ "$remaining" =~ ^([0-9]+)m([^a-z]|$) ]]; then
    total=$((total + ${BASH_REMATCH[1]} * 60))
    remaining="${remaining#*m}"
    matched=true
  fi
  if [[ "$remaining" =~ ^([0-9]+)s ]]; then
    total=$((total + ${BASH_REMATCH[1]}))
    remaining="${remaining#*s}"
    matched=true
  fi

  if $matched && [[ -z "$remaining" ]]; then
    echo "$total"
    return 0
  fi

  return 1
}

parse_absolute() {
  local input="$1"
  local hour min

  if [[ "$input" =~ ^([0-9]{1,2}):([0-9]{2})$ ]]; then
    hour="${BASH_REMATCH[1]}"
    min="${BASH_REMATCH[2]}"
  elif [[ "$input" =~ ^([0-9]{1,2})(:([0-9]{2}))?(am|pm)$ ]]; then
    hour="${BASH_REMATCH[1]}"
    min="${BASH_REMATCH[3]:-00}"
    local ampm="${BASH_REMATCH[4]}"
    if [[ "$ampm" == "pm" && "$hour" -ne 12 ]]; then
      hour=$((hour + 12))
    elif [[ "$ampm" == "am" && "$hour" -eq 12 ]]; then
      hour=0
    fi
  else
    return 1
  fi

  if [[ "$hour" -gt 23 || "$min" -gt 59 ]]; then
    echo "Error: invalid time '${input}'" >&2
    exit 1
  fi

  local target_epoch now_epoch diff
  target_epoch=$(date -j -f "%H:%M:%S" "$(printf '%02d:%02d:00' "$hour" "$min")" +%s 2>/dev/null)
  now_epoch=$(date +%s)
  diff=$((target_epoch - now_epoch))

  if [[ $diff -le 0 ]]; then
    echo "Error: ${input} has already passed today" >&2
    exit 1
  fi

  echo "$diff"
  return 0
}

INPUT="$1"
shift

if DURATION=$(parse_relative "$INPUT"); then
  :
elif DURATION=$(parse_absolute "$INPUT"); then
  :
else
  echo "Error: cannot parse '${INPUT}'" >&2
  echo ""
  usage
fi

if [[ "$DURATION" -le 0 ]]; then
  echo "Error: duration must be greater than 0" >&2
  exit 1
fi

MESSAGE="${*:-Times up!}"

TARGET_TIME=$(date -j -v+"${DURATION}S" +%H:%M)
DISPLAY_DUR=$(format_duration "$DURATION")
echo "⏰ ${DISPLAY_DUR} later (${TARGET_TIME}) — \"${MESSAGE}\""

ESCAPED_MSG="${MESSAGE//\\/\\\\}"
ESCAPED_MSG="${ESCAPED_MSG//\"/\\\"}"

(
  sleep "$DURATION"
  osascript -e "display notification \"${ESCAPED_MSG}\" with title \"Reminder\" sound name \"Glass\""
) &

echo "   PID: $! (kill $! to cancel)"

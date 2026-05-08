#!/bin/bash
# slack-scheduled-message.sh — helper for the slack-scheduled-message Claude Code skill.
# Deterministic parts (time math, env var lookup, cache I/O) live here so the SKILL.md
# stays short and the model is not regenerating the same bash on every invocation.
#
# Subcommands:
#   prepare <YYYY-MM-DD> <HH:MM> [custom-name]   → emit KEY=VALUE context lines
#   save-channel <slack-id>                       → write cache file

set -euo pipefail

CACHE_DIR="$HOME/.config/slack-scheduled-message"
CACHE_FILE="$CACHE_DIR/channel_id"

usage() {
  cat <<'USAGE' >&2
Usage:
  slack-scheduled-message.sh prepare <YYYY-MM-DD> <HH:MM> [custom-name]
  slack-scheduled-message.sh save-channel <slack-id>
USAGE
  exit 1
}

cmd="${1:-}"
shift || true

case "$cmd" in
  prepare)
    [[ $# -ge 2 ]] || usage
    DATE="$1"; TIME="$2"; CUSTOM_NAME="${3:-}"

    POST_AT=$(TZ=Asia/Seoul date -j -f '%Y-%m-%d %H:%M' "$DATE $TIME" '+%s' 2>/dev/null) \
      || { echo "ERROR: invalid date/time: $DATE $TIME" >&2; exit 2; }

    NOW=$(date +%s)
    DELTA=$((POST_AT - NOW))
    (( DELTA >= 120 )) || { echo "ERROR: post_at must be at least 2 minutes ahead (got ${DELTA}s)" >&2; exit 3; }
    (( DELTA <= 120 * 86400 )) || { echo "ERROR: Slack schedules max 120 days out (got $((DELTA / 86400))d)" >&2; exit 4; }

    SESSION_NAME=$(python3 - <<'PY' 2>/dev/null || true
import json, glob, os
sid = os.environ.get('CLAUDE_CODE_SESSION_ID', '')
if not sid:
    raise SystemExit
for f in glob.glob(os.path.expanduser('~/.claude/sessions/*.json')):
    try:
        d = json.load(open(f))
        if d.get('sessionId') == sid and d.get('name'):
            print(d['name'])
            break
    except Exception:
        pass
PY
)

    if [[ -n "$CUSTOM_NAME" ]]; then
      RESUME_TARGET="$CUSTOM_NAME"; RESUME_SOURCE="user_custom"
    elif [[ -n "$SESSION_NAME" ]]; then
      RESUME_TARGET="$SESSION_NAME"; RESUME_SOURCE="session_name"
    elif [[ -n "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
      RESUME_TARGET="$CLAUDE_CODE_SESSION_ID"; RESUME_SOURCE="session_id"
    else
      echo "ERROR: cannot resolve resume target (no custom name, no session name, no \$CLAUDE_CODE_SESSION_ID)" >&2
      exit 5
    fi

    CACHED_CHANNEL_ID=$(cat "$CACHE_FILE" 2>/dev/null || true)

    cat <<EOF
PWD=$PWD
SESSION_ID=${CLAUDE_CODE_SESSION_ID:-}
SESSION_NAME=$SESSION_NAME
POST_AT=$POST_AT
POST_AT_HUMAN=$(TZ=Asia/Seoul date -r "$POST_AT" '+%Y-%m-%d %H:%M:%S %Z (%a)')
RESUME_TARGET=$RESUME_TARGET
RESUME_SOURCE=$RESUME_SOURCE
CACHED_CHANNEL_ID=$CACHED_CHANNEL_ID
EOF
    ;;

  save-channel)
    [[ $# -eq 1 ]] || usage
    mkdir -p "$CACHE_DIR"
    printf '%s' "$1" > "$CACHE_FILE"
    echo "saved: $1 → $CACHE_FILE"
    ;;

  *)
    usage
    ;;
esac

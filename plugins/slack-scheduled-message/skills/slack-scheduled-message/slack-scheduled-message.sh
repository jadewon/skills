#!/bin/bash
# slack-scheduled-message.sh — helper for the slack-scheduled-message Claude Code skill.
# Deterministic parts (time math, env var lookup, cache I/O) live here so the SKILL.md
# stays short and the model is not regenerating the same bash on every invocation.
#
# Subcommands:
#   prepare <YYYY-MM-DD> <HH:MM> [custom-name]   → emit KEY=VALUE context lines
#   save-channel <slack-id>                       → write cache file
#   list-scheduled <channel_id>                    → chat.scheduledMessages.list (needs SLACK_USER_TOKEN)
#   cancel-scheduled <channel_id> <scheduled_id>   → chat.deleteScheduledMessage (needs SLACK_USER_TOKEN)

set -euo pipefail

CACHE_DIR="$HOME/.config/slack-scheduled-message"
CACHE_FILE="$CACHE_DIR/channel_id"

usage() {
  cat <<'USAGE' >&2
Usage:
  slack-scheduled-message.sh prepare <YYYY-MM-DD> <HH:MM> [custom-name]
  slack-scheduled-message.sh save-channel <slack-id>
  slack-scheduled-message.sh list-scheduled <channel_id>
  slack-scheduled-message.sh cancel-scheduled <channel_id> <scheduled_message_id>
USAGE
  exit 1
}

# list-scheduled / cancel-scheduled 는 slack_schedule_message MCP 도구엔 없는
# chat.scheduledMessages.list / chat.deleteScheduledMessage 호출이라 user 토큰이 필요하다.
# slack-edit-message 스킬과 동일한 순서로 .env 를 찾는다 (공유 토큰 우선).
load_user_token() {
  local script_dir env_file candidate
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  env_file="${SLACK_SCHEDULED_MESSAGE_ENV:-}"
  if [[ -z "$env_file" ]]; then
    for candidate in "$HOME/.config/slack-user-token/.env" "$HOME/.config/slack-scheduled-message/.env" "$script_dir/.env"; do
      [[ -f "$candidate" ]] && { env_file="$candidate"; break; }
    done
  fi
  [[ -f "$env_file" ]] || { echo "ERROR: .env not found. Tried SLACK_SCHEDULED_MESSAGE_ENV, ~/.config/slack-user-token/.env, ~/.config/slack-scheduled-message/.env, ${script_dir}/.env" >&2; exit 1; }
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
  : "${SLACK_USER_TOKEN:?SLACK_USER_TOKEN (xoxp-...) required in .env}"
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

  list-scheduled)
    [[ $# -eq 1 ]] || usage
    load_user_token
    channel="$1"
    resp=$(curl -fsS -G https://slack.com/api/chat.scheduledMessages.list \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      --data-urlencode "channel=${channel}")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  cancel-scheduled)
    [[ $# -eq 2 ]] || usage
    load_user_token
    channel="$1"; scheduled_id="$2"
    resp=$(curl -fsS -X POST https://slack.com/api/chat.deleteScheduledMessage \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      -H 'Content-Type: application/json; charset=utf-8' \
      --data "$(jq -n --arg channel "$channel" --arg id "$scheduled_id" \
        '{channel:$channel, scheduled_message_id:$id}')")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  *)
    usage
    ;;
esac

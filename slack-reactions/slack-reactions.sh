#!/usr/bin/env bash
set -euo pipefail

# Slack 반응(이모지) 제거/조회 — claude_ai Slack MCP 도구셋엔 add_reaction/get_reactions 는
# 있어도 reactions.remove/reactions.list 가 없어서 xoxp(user) 토큰으로 Slack Web API 를 직접 호출한다.
#
# Usage:
#   slack-reactions.sh remove <channel_id> <ts> <emoji_name>
#   slack-reactions.sh list [user_id]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SLACK_REACTIONS_ENV:-}"
if [[ -z "$ENV_FILE" ]]; then
  for candidate in "$HOME/.config/slack-user-token/.env" "$HOME/.config/slack-reactions/.env" "$SCRIPT_DIR/.env"; do
    [[ -f "$candidate" ]] && { ENV_FILE="$candidate"; break; }
  done
fi
[[ -f "$ENV_FILE" ]] || { echo "ERROR: .env not found. Tried SLACK_REACTIONS_ENV, ~/.config/slack-user-token/.env, ~/.config/slack-reactions/.env, ${SCRIPT_DIR}/.env" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${SLACK_USER_TOKEN:?SLACK_USER_TOKEN (xoxp-...) required in .env}"

usage() {
  cat <<'USAGE' >&2
Usage:
  slack-reactions.sh remove <channel_id> <ts> <emoji_name>
  slack-reactions.sh list [user_id]
USAGE
  exit 1
}

cmd="${1:-}"
shift || true

case "$cmd" in
  remove)
    [[ $# -eq 3 ]] || usage
    channel="$1"; ts="$2"; name="$3"
    resp=$(curl -fsS -X POST https://slack.com/api/reactions.remove \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      -H 'Content-Type: application/json; charset=utf-8' \
      --data "$(jq -n --arg channel "$channel" --arg timestamp "$ts" --arg name "$name" \
        '{channel:$channel, timestamp:$timestamp, name:$name}')")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  list)
    [[ $# -le 1 ]] || usage
    if [[ $# -eq 1 ]]; then
      resp=$(curl -fsS -G https://slack.com/api/reactions.list \
        -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
        --data-urlencode "user=$1")
    else
      resp=$(curl -fsS -G https://slack.com/api/reactions.list \
        -H "Authorization: Bearer ${SLACK_USER_TOKEN}")
    fi
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  *)
    usage
    ;;
esac

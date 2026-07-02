#!/usr/bin/env bash
set -euo pipefail

# Slack 메시지 수정/삭제 — claude_ai Slack MCP 도구셋엔 chat.update/chat.delete 가 없어
# xoxp(user) 토큰으로 Slack Web API 를 직접 호출한다. 본인이 보낸 메시지만 수정/삭제 가능
# (bot 토큰으로는 불가, Slack 정책상 user 토큰 필요).
#
# Usage:
#   slack-edit-message.sh whoami
#   slack-edit-message.sh update <channel_id> <ts> <new_text>
#   slack-edit-message.sh delete <channel_id> <ts>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SLACK_EDIT_MESSAGE_ENV:-}"
if [[ -z "$ENV_FILE" ]]; then
  for candidate in "$HOME/.config/slack-edit-message/.env" "$SCRIPT_DIR/.env"; do
    [[ -f "$candidate" ]] && { ENV_FILE="$candidate"; break; }
  done
fi
[[ -f "$ENV_FILE" ]] || { echo "ERROR: .env not found. Tried SLACK_EDIT_MESSAGE_ENV, ~/.config/slack-edit-message/.env, ${SCRIPT_DIR}/.env" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${SLACK_USER_TOKEN:?SLACK_USER_TOKEN (xoxp-...) required in .env}"

usage() {
  cat <<'USAGE' >&2
Usage:
  slack-edit-message.sh whoami
  slack-edit-message.sh update <channel_id> <ts> <new_text>
  slack-edit-message.sh delete <channel_id> <ts>
USAGE
  exit 1
}

cmd="${1:-}"
shift || true

case "$cmd" in
  whoami)
    curl -fsS -X POST https://slack.com/api/auth.test \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}"
    echo
    ;;

  update)
    [[ $# -eq 3 ]] || usage
    channel="$1"; ts="$2"; text="$3"
    resp=$(curl -fsS -X POST https://slack.com/api/chat.update \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      -H 'Content-Type: application/json; charset=utf-8' \
      --data "$(jq -n --arg channel "$channel" --arg ts "$ts" --arg text "$text" \
        '{channel:$channel, ts:$ts, text:$text}')")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  delete)
    [[ $# -eq 2 ]] || usage
    channel="$1"; ts="$2"
    resp=$(curl -fsS -X POST https://slack.com/api/chat.delete \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      -H 'Content-Type: application/json; charset=utf-8' \
      --data "$(jq -n --arg channel "$channel" --arg ts "$ts" \
        '{channel:$channel, ts:$ts}')")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  *)
    usage
    ;;
esac

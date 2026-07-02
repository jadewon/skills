#!/usr/bin/env bash
set -euo pipefail

# Slack 메시지 핀 고정/해제/목록 — claude_ai Slack MCP 도구셋엔 pins.* 가 없어
# xoxp(user) 토큰으로 Slack Web API 를 직접 호출한다.
#   pins.add / pins.remove → User Token Scope: pins:write
#   pins.list             → User Token Scope: pins:read
#
# Usage:
#   slack-pins.sh add <channel> <ts>
#   slack-pins.sh remove <channel> <ts>
#   slack-pins.sh list <channel>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SLACK_PINS_ENV:-}"
if [[ -z "$ENV_FILE" ]]; then
  for candidate in "$HOME/.config/slack-user-token/.env" "$HOME/.config/slack-pins/.env" "$SCRIPT_DIR/.env"; do
    [[ -f "$candidate" ]] && { ENV_FILE="$candidate"; break; }
  done
fi
[[ -f "$ENV_FILE" ]] || { echo "ERROR: .env not found. Tried SLACK_PINS_ENV, ~/.config/slack-user-token/.env, ~/.config/slack-pins/.env, ${SCRIPT_DIR}/.env" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${SLACK_USER_TOKEN:?SLACK_USER_TOKEN (xoxp-...) required in .env}"

usage() {
  cat <<'USAGE' >&2
Usage:
  slack-pins.sh add <channel> <ts>
  slack-pins.sh remove <channel> <ts>
  slack-pins.sh list <channel>
USAGE
  exit 1
}

cmd="${1:-}"
shift || true

case "$cmd" in
  add)
    [[ $# -eq 2 ]] || usage
    channel="$1"; ts="$2"
    resp=$(curl -fsS -X POST https://slack.com/api/pins.add \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      -H 'Content-Type: application/json; charset=utf-8' \
      --data "$(jq -n --arg channel "$channel" --arg ts "$ts" \
        '{channel:$channel, timestamp:$ts}')")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  remove)
    [[ $# -eq 2 ]] || usage
    channel="$1"; ts="$2"
    resp=$(curl -fsS -X POST https://slack.com/api/pins.remove \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      -H 'Content-Type: application/json; charset=utf-8' \
      --data "$(jq -n --arg channel "$channel" --arg ts "$ts" \
        '{channel:$channel, timestamp:$ts}')")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  list)
    [[ $# -eq 1 ]] || usage
    channel="$1"
    resp=$(curl -fsS -G https://slack.com/api/pins.list \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      --data-urlencode "channel=$channel")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  *)
    usage
    ;;
esac

#!/usr/bin/env bash
set -euo pipefail

# Slack 유틸리티 모음 — claude_ai Slack MCP 도구셋에 없는 단일 엔드포인트들을
# xoxp(user) 토큰으로 Slack Web API 직접 호출로 채운다.
#   permalink:      chat.getPermalink     — 메시지의 공유 가능한 퍼머링크 생성 (읽기 전용)
#   delete-canvas:  canvases.delete       — 캔버스 삭제 (되돌릴 수 없음)
#   read:           conversations.history — 메시지 원본 JSON 조회 (attachments/blocks 포함, claude_ai MCP는 text만 줌)
#
# Usage:
#   slack-utils.sh permalink <channel_id> <ts>
#   slack-utils.sh delete-canvas <canvas_id>
#   slack-utils.sh read <channel_id> <ts>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SLACK_UTILS_ENV:-}"
if [[ -z "$ENV_FILE" ]]; then
  for candidate in "$HOME/.config/slack-user-token/.env" "$HOME/.config/slack-utils/.env" "$SCRIPT_DIR/.env"; do
    [[ -f "$candidate" ]] && { ENV_FILE="$candidate"; break; }
  done
fi
[[ -f "$ENV_FILE" ]] || { echo "ERROR: .env not found. Tried SLACK_UTILS_ENV, ~/.config/slack-user-token/.env, ~/.config/slack-utils/.env, ${SCRIPT_DIR}/.env" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${SLACK_USER_TOKEN:?SLACK_USER_TOKEN (xoxp-...) required in .env}"

usage() {
  cat <<'USAGE' >&2
Usage:
  slack-utils.sh permalink <channel_id> <ts>
  slack-utils.sh delete-canvas <canvas_id>
  slack-utils.sh read <channel_id> <ts>
USAGE
  exit 1
}

cmd="${1:-}"
shift || true

case "$cmd" in
  permalink)
    [[ $# -eq 2 ]] || usage
    channel="$1"; ts="$2"
    resp=$(curl -fsS -G https://slack.com/api/chat.getPermalink \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      --data-urlencode "channel=$channel" \
      --data-urlencode "message_ts=$ts")
    if [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]]; then
      echo "$resp" | jq -r '.permalink'
    else
      echo "$resp" >&2
      exit 2
    fi
    ;;

  delete-canvas)
    [[ $# -eq 1 ]] || usage
    canvas_id="$1"
    resp=$(curl -fsS -X POST https://slack.com/api/canvases.delete \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      -H 'Content-Type: application/json; charset=utf-8' \
      --data "$(jq -n --arg canvas_id "$canvas_id" \
        '{canvas_id:$canvas_id}')")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  read)
    [[ $# -eq 2 ]] || usage
    channel="$1"; ts="$2"
    resp=$(curl -fsS -G https://slack.com/api/conversations.history \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      --data-urlencode "channel=$channel" \
      --data-urlencode "latest=$ts" \
      --data-urlencode "inclusive=true" \
      --data-urlencode "limit=1")
    if [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]]; then
      echo "$resp" | jq '.messages[0]'
    else
      echo "$resp" >&2
      exit 2
    fi
    ;;

  *)
    usage
    ;;
esac

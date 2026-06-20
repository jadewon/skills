#!/usr/bin/env bash
# cat-post.sh — Slack chat.postMessage 로 메시지를 게시한다 (봇 토큰).
#
# 봇 토큰/채널은 .env 의 SLACK_BOT_TOKEN / SLACK_CHANNEL 에서 로드한다 —
# jadewon/skills 는 PUBLIC 이라 시크릿을 스크립트에 박지 않는다. .env.example 참고.
# cat-fact-daily / cat-photo-daily 가 공유하는 발송 헬퍼 (서버 .env = ~/.config/cat-daily/.env).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${CAT_DAILY_ENV:-}"
if [[ -z "$ENV_FILE" ]]; then
  for candidate in "$HOME/.config/cat-daily/.env" "$SCRIPT_DIR/.env"; do
    [[ -f "$candidate" ]] && { ENV_FILE="$candidate"; break; }
  done
fi
[[ -f "$ENV_FILE" ]] || { echo "ERROR: .env not found. Tried CAT_DAILY_ENV, ~/.config/cat-daily/.env, ${SCRIPT_DIR}/.env" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${SLACK_BOT_TOKEN:?SLACK_BOT_TOKEN required in .env}"
: "${SLACK_CHANNEL:?SLACK_CHANNEL required in .env}"

MSG="${1:?usage: cat-post.sh <message>}"

RESP=$(curl -sS --max-time 10 -X POST https://slack.com/api/chat.postMessage \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  -H "Content-Type: application/json; charset=utf-8" \
  --data "$(jq -n --arg channel "$SLACK_CHANNEL" --arg text "$MSG" '{channel:$channel, text:$text}')")

ok=$(echo "$RESP" | jq -r '.ok')
if [[ "$ok" != "true" ]]; then
  echo "ERROR: Slack rejected: $(echo "$RESP" | jq -r '.error // .')" >&2
  exit 3
fi
echo "ok"

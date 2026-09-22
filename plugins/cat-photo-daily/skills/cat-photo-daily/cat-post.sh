#!/usr/bin/env bash
# cat-post.sh — Slack chat.postMessage 로 메시지를 게시한다 (봇 토큰).
#
# 봇 토큰/채널은 .env 의 SLACK_BOT_TOKEN / SLACK_CHANNEL 에서 로드한다 —
# jadewon/skills 는 PUBLIC 이라 시크릿을 스크립트에 박지 않는다. .env.example 참고.
# cat-photo-daily 전용 발송 헬퍼 (서버 .env = ~/.config/cat-daily/.env — cat-fact-daily 와 같은 파일).
#
# usage: cat-post.sh <message> [image-url]
# image-url 을 주면 Slack image block 으로 보낸다. <url|라벨> 형태의 링크는 Slack 이
# 이미지 미리보기로 펼치지 않아서 사진이 안 보였다 (2026-09-22).
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

MSG="${1:?usage: cat-post.sh <message> [image-url]}"
IMG_URL="${2:-}"

if [[ -n "$IMG_URL" ]]; then
  # text 는 알림용 fallback, blocks 가 실제 렌더링이다. image block 이 사진을 펼친다.
  PAYLOAD=$(jq -n --arg channel "$SLACK_CHANNEL" --arg text "$MSG" --arg img "$IMG_URL" \
    '{channel:$channel, text:$text, blocks:[
       {type:"section", text:{type:"mrkdwn", text:$text}},
       {type:"image", image_url:$img, alt_text:"오늘의 랜덤 냥사진"}
     ]}')
else
  PAYLOAD=$(jq -n --arg channel "$SLACK_CHANNEL" --arg text "$MSG" '{channel:$channel, text:$text}')
fi

RESP=$(curl -sS --max-time 10 -X POST https://slack.com/api/chat.postMessage \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  -H "Content-Type: application/json; charset=utf-8" \
  --data "$PAYLOAD")

ok=$(echo "$RESP" | jq -r '.ok')
if [[ "$ok" != "true" ]]; then
  echo "ERROR: Slack rejected: $(echo "$RESP" | jq -r '.error // .')" >&2
  exit 3
fi
echo "ok"

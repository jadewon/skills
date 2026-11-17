#!/usr/bin/env bash
# dog-post.sh — Slack chat.postMessage 로 메시지를 게시한다 (봇 토큰).
#
# 봇 토큰/채널은 .env 의 SLACK_BOT_TOKEN / SLACK_CHANNEL 에서 로드한다 —
# jadewon/skills 는 PUBLIC 이라 시크릿을 스크립트에 박지 않는다. .env.example 참고.
# dog-photo-daily 전용 발송 헬퍼 (서버 .env = ~/.config/dog-daily/.env — dog-fact-daily 와 같은 파일).
#
# usage: dog-post.sh <message> [image-path]
#
# image-path 를 주면 그 파일을 Slack 에 업로드해서 코멘트와 함께 올린다. 링크로 보내지 않는다.
# 링크로 보내면 사진은 Slack 의 링크 미리보기(unfurl)가 붙어야만 보이는데, 그 미리보기는 Slack 쪽
# 사정으로 붙지 않을 수 있고 봇은 그걸 알 수 없다. 업로드한 파일은 unfurl 을 거치지 않으므로
# 사진이 항상 메시지에 붙는다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${DOG_DAILY_ENV:-}"
if [[ -z "$ENV_FILE" ]]; then
  for candidate in "$HOME/.config/dog-daily/.env" "$SCRIPT_DIR/.env"; do
    [[ -f "$candidate" ]] && { ENV_FILE="$candidate"; break; }
  done
fi
[[ -f "$ENV_FILE" ]] || { echo "ERROR: .env not found. Tried DOG_DAILY_ENV, ~/.config/dog-daily/.env, ${SCRIPT_DIR}/.env" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${SLACK_BOT_TOKEN:?SLACK_BOT_TOKEN required in .env}"
: "${SLACK_CHANNEL:?SLACK_CHANNEL required in .env}"

MSG="${1:?usage: dog-post.sh <message> [image-path]}"
IMG_PATH="${2:-}"

fail() { echo "ERROR: $1" >&2; exit 3; }

if [[ -n "$IMG_PATH" ]]; then
  [[ -f "$IMG_PATH" ]] || fail "image not found: $IMG_PATH"
  LEN=$(wc -c < "$IMG_PATH" | tr -d ' ')

  # 업로드는 3단계다: URL 발급 → 바이트 전송 → 채널에 게시(코멘트 동봉).
  UP=$(curl -sS --max-time 10 -H "Authorization: Bearer $SLACK_BOT_TOKEN" --get \
    --data-urlencode "filename=$(basename "$IMG_PATH")" --data-urlencode "length=$LEN" \
    https://slack.com/api/files.getUploadURLExternal)
  [[ "$(echo "$UP" | jq -r '.ok')" == "true" ]] || fail "getUploadURLExternal: $(echo "$UP" | jq -r '.error // .')"

  curl -fsS --max-time 30 -F "file=@$IMG_PATH" "$(echo "$UP" | jq -r '.upload_url')" > /dev/null \
    || fail "file bytes upload failed"

  RESP=$(curl -sS --max-time 15 -X POST https://slack.com/api/files.completeUploadExternal \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H "Content-Type: application/json; charset=utf-8" \
    --data "$(jq -n --arg fid "$(echo "$UP" | jq -r '.file_id')" --arg ch "$SLACK_CHANNEL" --arg c "$MSG" \
      '{files:[{id:$fid, title:"오늘의 랜덤 댕댕이 사진"}], channel_id:$ch, initial_comment:$c}')")
else
  RESP=$(curl -sS --max-time 10 -X POST https://slack.com/api/chat.postMessage \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H "Content-Type: application/json; charset=utf-8" \
    --data "$(jq -n --arg channel "$SLACK_CHANNEL" --arg text "$MSG" '{channel:$channel, text:$text}')")
fi

ok=$(echo "$RESP" | jq -r '.ok')
if [[ "$ok" != "true" ]]; then
  echo "ERROR: Slack rejected: $(echo "$RESP" | jq -r '.error // .')" >&2
  exit 3
fi
echo "ok"

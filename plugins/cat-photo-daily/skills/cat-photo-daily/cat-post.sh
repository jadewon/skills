#!/usr/bin/env bash
# cat-post.sh — Slack chat.postMessage 로 메시지를 게시한다 (봇 토큰).
#
# 봇 토큰/채널은 .env 의 SLACK_BOT_TOKEN / SLACK_CHANNEL 에서 로드한다 —
# jadewon/skills 는 PUBLIC 이라 시크릿을 스크립트에 박지 않는다. .env.example 참고.
# cat-photo-daily 전용 발송 헬퍼 (서버 .env = ~/.config/cat-daily/.env — cat-fact-daily 와 같은 파일).
#
# usage: cat-post.sh <message> [image-path]
#
# image-path 를 주면 그 파일을 Slack 에 업로드해서 코멘트와 함께 올린다. 링크로 보내지 않는다.
# 2026-09-16 까지는 <URL|라벨> 링크를 Slack 이 자동으로 펼쳐 사진을 보여줬다. 2026-09-17 부터
# 같은 코드·같은 봇·같은 URL 인데 미리보기가 사라졌다 (채널 200건 실측: 04-01~09-16 전건 첨부
# 있음, 09-17 이후 0건). 레포 전체에 unfurl 설정이 존재한 적 없고, 앱 unfurl 도메인과 워크스페이스
# 차단 목록도 비어 있다. wsrv.nl 프록시로 도메인을 바꿔도 안 붙는다 — 이 앱의 링크 자동 미리보기가
# Slack 쪽에서 멈췄다. 업로드는 unfurl 경로를 타지 않으므로 그 변화에 영향받지 않는다.
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

MSG="${1:?usage: cat-post.sh <message> [image-path]}"
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

  curl -sS --max-time 30 -F "file=@$IMG_PATH" "$(echo "$UP" | jq -r '.upload_url')" > /dev/null \
    || fail "file bytes upload failed"

  RESP=$(curl -sS --max-time 15 -X POST https://slack.com/api/files.completeUploadExternal \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H "Content-Type: application/json; charset=utf-8" \
    --data "$(jq -n --arg fid "$(echo "$UP" | jq -r '.file_id')" --arg ch "$SLACK_CHANNEL" --arg c "$MSG" \
      '{files:[{id:$fid, title:"오늘의 랜덤 냥사진"}], channel_id:$ch, initial_comment:$c}')")
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

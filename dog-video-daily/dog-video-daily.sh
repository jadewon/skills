#!/usr/bin/env bash
# dog-video-daily.sh — Mastodon 강아지 해시태그에서 좋아요가 가장 많은 영상을 골라 Slack 에 업로드한다.
# 선택·다운로드·업로드는 결정론 스크립트가 하고, 글 내용 → 한국어 한 줄 제목만 Haiku 로 만든다.
# 그래서 스킬(claude -p /...)이 아니라 cron 에서 이 스크립트를 직접 실행한다. Haiku 가 실패하면 제목 없이 올린다.
#
# 소스: Mastodon 공개 해시태그 타임라인 (키/가입 불필요). favourites_count 가 좋아요 수다.
# 2026-11-19 조사 시 Reddit·Bluesky 는 403, Giphy 공개키는 BANNED, Pexels 는 신규 키 발급 중단이었다.
# 같은 영상을 다시 올리지 않도록 게시한 글 URI 를 상태 파일에 쌓는다.
#
# usage: dog-video-daily.sh [--dry-run]   (--dry-run: 고르고 내려받기까지만, Slack 전송 안 함)
set -euo pipefail

TAGS=(dogsofmastodon dogs puppy)
TITLE="오늘의 인기 댕댕이 영상"
LABEL="댕댕이 영상"
NAME=dog-video-daily
ENV_FILE="${DOG_DAILY_ENV:-$HOME/.config/dog-daily/.env}"

INSTANCE="${MASTODON_INSTANCE:-https://mastodon.social}"
PAGES=5
MAX_AGE_DAYS=7
MAX_BYTES=$((100 * 1024 * 1024))
CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/$NAME"
DRY_RUN=0; [[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

fail() { echo "ERROR: $1" >&2; exit 3; }

[[ -f "$ENV_FILE" ]] || fail ".env not found: $ENV_FILE"
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
: "${SLACK_BOT_TOKEN:?SLACK_BOT_TOKEN required in .env}"
: "${SLACK_CHANNEL:?SLACK_CHANNEL required in .env}"

TODAY=$(date +%Y-%m-%d)
HOLIDAY=$(curl -s --max-time 10 "https://hiworks-production.up.railway.app/hiworks/holiday?startDate=$TODAY&endDate=$TODAY" || true)
if echo "$HOLIDAY" | jq -e 'type == "array" and length > 0' > /dev/null 2>&1; then
  echo "공휴일 스킵"; exit 0
fi

mkdir -p "$STATE_DIR"
POSTED="$STATE_DIR/posted.txt"
touch "$POSTED"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for tag in "${TAGS[@]}"; do
  max=""
  for _ in $(seq "$PAGES"); do
    page=$(curl -sf --max-time 15 "$INSTANCE/api/v1/timelines/tag/$tag?only_media=true&limit=40${max:+&max_id=$max}") || break
    echo "$page" | jq -c '.[]' >> "$TMP/posts.jsonl"
    max=$(echo "$page" | jq -r '.[-1].id // empty')
    [[ -n "$max" ]] || break
  done
done
[[ -s "$TMP/posts.jsonl" ]] || fail "Mastodon 에서 글을 하나도 못 가져왔다 ($INSTANCE)"

# 최근 MAX_AGE_DAYS 일 글 중 민감(CW) 표시된 글, 이미 올린 글은 제외하고 좋아요 순으로 정렬한다.
SINCE=$(date -u -d "$MAX_AGE_DAYS days ago" +%Y-%m-%dT%H:%M:%S)
jq -cs --rawfile posted "$POSTED" --arg since "$SINCE" '
  ($posted | split("\n")) as $seen
  | [ .[]
      | select(.created_at >= $since)
      | select((.sensitive | not) and (.spoiler_text // "") == "")
      | select(.uri as $u | $seen | index($u) | not)
      | . as $p
      | (.media_attachments | map(select(.type == "video")) | first) as $m
      | select($m != null)
      | {uri: $p.uri, link: ($p.url // $p.uri), fav: $p.favourites_count, video: $m.url,
         text: ($p.content | gsub("<[^>]*>"; " ") | gsub("\\s+"; " ")), alt: ($m.description // "")} ]
  | unique_by(.uri) | sort_by(-.fav) | .[:10][]' "$TMP/posts.jsonl" > "$TMP/candidates.jsonl"
[[ -s "$TMP/candidates.jsonl" ]] || fail "올릴 만한 새 영상이 없다"

while read -r c; do
  video_url=$(echo "$c" | jq -r '.video')
  ext="${video_url##*.}"; ext="${ext%%\?*}"
  file="$TMP/$NAME-$TODAY.$ext"
  curl -sfL --max-time 120 --max-filesize "$MAX_BYTES" -o "$file" "$video_url" || continue
  file -b --mime-type "$file" | grep -q '^video/' || continue

  fav=$(echo "$c" | jq -r '.fav'); link=$(echo "$c" | jq -r '.link')
  caption=""
  # 글·대체텍스트가 둘 다 비어 있으면 Haiku 가 지어낼 것밖에 없으니 제목 없이 올린다.
  if echo "$c" | jq -e '(.text + .alt) | test("\\S")' > /dev/null; then
    caption=$(echo "$c" | jq -r '"글: \(.text)\n영상 설명(alt): \(.alt)"' \
      | timeout 90 "$CLAUDE_BIN" -p --model haiku --tools "" --no-session-persistence --strict-mcp-config \
          --system-prompt "Mastodon 글과 영상 대체텍스트를 보고 영상이 어떤 내용인지 한국어 한 문장 제목으로 써라. 글에 있는 사실만 쓰고 추측·과장 금지. 해시태그·이모지·따옴표·마크다운 없이 그 문장만 출력." \
          "이 영상의 한국어 제목:" 2>/dev/null \
      | tr '\n*' '  ' | sed 's/^ *//; s/ *$//' || true)
  fi
  msg="오늘의 $LABEL · 좋아요 ${fav}개"
  [[ -n "$caption" ]] && msg="*${caption}*"$'\n'"$msg"
  echo "picked: $fav fav | $link | $(wc -c < "$file") bytes"
  echo "$msg"
  if (( DRY_RUN )); then cp "$file" "/tmp/$NAME.$ext"; echo "dry-run: /tmp/$NAME.$ext"; exit 0; fi

  UP=$(curl -sS --max-time 10 -H "Authorization: Bearer $SLACK_BOT_TOKEN" --get \
    --data-urlencode "filename=$(basename "$file")" --data-urlencode "length=$(wc -c < "$file" | tr -d ' ')" \
    https://slack.com/api/files.getUploadURLExternal)
  [[ "$(echo "$UP" | jq -r '.ok')" == "true" ]] || fail "getUploadURLExternal: $(echo "$UP" | jq -r '.error // .')"

  curl -fsS --max-time 300 -F "file=@$file" "$(echo "$UP" | jq -r '.upload_url')" > /dev/null \
    || fail "file bytes upload failed"

  RESP=$(curl -sS --max-time 30 -X POST https://slack.com/api/files.completeUploadExternal \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H "Content-Type: application/json; charset=utf-8" \
    --data "$(jq -n --arg fid "$(echo "$UP" | jq -r '.file_id')" --arg ch "$SLACK_CHANNEL" --arg c "$msg" --arg t "$TITLE" \
      '{files:[{id:$fid, title:$t}], channel_id:$ch, initial_comment:$c}')")
  [[ "$(echo "$RESP" | jq -r '.ok')" == "true" ]] || fail "Slack rejected: $(echo "$RESP" | jq -r '.error // .')"

  echo "$c" | jq -r '.uri' >> "$POSTED"
  echo "ok"
  exit 0
done < "$TMP/candidates.jsonl"

fail "후보 영상을 하나도 내려받지 못했다"

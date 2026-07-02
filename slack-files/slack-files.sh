#!/usr/bin/env bash
set -euo pipefail

# Slack 파일 업로드/삭제 — claude_ai Slack MCP 도구셋엔 파일 업로드/삭제가 없어
# xoxp(user) 토큰으로 Slack Web API 를 직접 호출한다.
# 업로드는 deprecated 된 files.upload 대신 external-upload 3단계 흐름을 쓴다:
#   1) files.getUploadURLExternal 로 upload_url + file_id 획득
#   2) upload_url 에 파일 바이트를 raw binary(application/octet-stream)로 POST
#   3) files.completeUploadExternal 로 file_id 를 채널에 공유하며 마무리
#
# Usage:
#   slack-files.sh upload <channel_id> <file_path> [title] [comment]
#   slack-files.sh delete <file_id>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SLACK_FILES_ENV:-}"
if [[ -z "$ENV_FILE" ]]; then
  for candidate in "$HOME/.config/slack-user-token/.env" "$HOME/.config/slack-files/.env" "$SCRIPT_DIR/.env"; do
    [[ -f "$candidate" ]] && { ENV_FILE="$candidate"; break; }
  done
fi
[[ -f "$ENV_FILE" ]] || { echo "ERROR: .env not found. Tried SLACK_FILES_ENV, ~/.config/slack-user-token/.env, ~/.config/slack-files/.env, ${SCRIPT_DIR}/.env" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${SLACK_USER_TOKEN:?SLACK_USER_TOKEN (xoxp-...) required in .env}"

usage() {
  cat <<'USAGE' >&2
Usage:
  slack-files.sh upload <channel_id> <file_path> [title] [comment]
  slack-files.sh delete <file_id>
USAGE
  exit 1
}

cmd="${1:-}"
shift || true

case "$cmd" in
  upload)
    [[ $# -ge 2 && $# -le 4 ]] || usage
    channel="$1"; file_path="$2"; title="${3:-}"; comment="${4:-}"

    [[ -f "$file_path" ]] || { echo "ERROR: file not found: $file_path" >&2; exit 2; }
    [[ -r "$file_path" ]] || { echo "ERROR: file not readable: $file_path" >&2; exit 2; }

    fname="$(basename "$file_path")"
    flen="$(wc -c < "$file_path" | tr -d '[:space:]')"

    # 1) upload URL 획득
    step1=$(curl -fsS -X POST https://slack.com/api/files.getUploadURLExternal \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      --data-urlencode "filename=${fname}" \
      --data-urlencode "length=${flen}")
    if [[ "$(echo "$step1" | jq -r '.ok')" != "true" ]]; then
      echo "$step1" >&2
      echo "ERROR: files.getUploadURLExternal failed" >&2
      exit 2
    fi
    upload_url="$(echo "$step1" | jq -r '.upload_url')"
    file_id="$(echo "$step1" | jq -r '.file_id')"

    # 2) 파일 바이트를 upload_url 에 raw binary 로 POST (성공 시 HTTP 200 "OK - <n>")
    curl -fsS -X POST "$upload_url" \
      -H 'Content-Type: application/octet-stream' \
      --data-binary "@${file_path}" >/dev/null \
      || { echo "ERROR: uploading file bytes to upload_url failed (file_id=${file_id})" >&2; exit 2; }

    # 3) 업로드 마무리 + 채널 공유
    payload=$(jq -n \
      --arg id "$file_id" \
      --arg title "$title" \
      --arg channel "$channel" \
      --arg comment "$comment" \
      '{files: [ ({id: $id} + (if $title != "" then {title: $title} else {} end)) ], channel_id: $channel}
       + (if $comment != "" then {initial_comment: $comment} else {} end)')
    step3=$(curl -fsS -X POST https://slack.com/api/files.completeUploadExternal \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      -H 'Content-Type: application/json; charset=utf-8' \
      --data "$payload")
    echo "$step3"
    [[ "$(echo "$step3" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  delete)
    [[ $# -eq 1 ]] || usage
    file_id="$1"
    resp=$(curl -fsS -X POST https://slack.com/api/files.delete \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      -H 'Content-Type: application/json; charset=utf-8' \
      --data "$(jq -n --arg file "$file_id" '{file: $file}')")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  *)
    usage
    ;;
esac

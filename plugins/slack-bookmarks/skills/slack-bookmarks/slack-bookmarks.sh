#!/usr/bin/env bash
set -euo pipefail

# Slack 채널 북마크(상단 링크 바) 관리 — claude_ai Slack MCP 도구셋엔 bookmarks.* 가
# 없어 xoxp(user) 토큰으로 Slack Web API 를 직접 호출한다. (bot 토큰으로도 되지만
# 다른 slack-* 스킬과 토큰을 공유하려고 user 토큰을 쓴다.)
#
# Usage:
#   slack-bookmarks.sh list   <channel_id>
#   slack-bookmarks.sh add    <channel_id> <title> <url>
#   slack-bookmarks.sh edit   <channel_id> <bookmark_id> <title> <url>
#   slack-bookmarks.sh remove <channel_id> <bookmark_id>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SLACK_BOOKMARKS_ENV:-}"
if [[ -z "$ENV_FILE" ]]; then
  for candidate in "$HOME/.config/slack-user-token/.env" "$HOME/.config/slack-bookmarks/.env" "$SCRIPT_DIR/.env"; do
    [[ -f "$candidate" ]] && { ENV_FILE="$candidate"; break; }
  done
fi
[[ -f "$ENV_FILE" ]] || { echo "ERROR: .env not found. Tried SLACK_BOOKMARKS_ENV, ~/.config/slack-user-token/.env, ~/.config/slack-bookmarks/.env, ${SCRIPT_DIR}/.env" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${SLACK_USER_TOKEN:?SLACK_USER_TOKEN (xoxp-...) required in .env}"

usage() {
  cat <<'USAGE' >&2
Usage:
  slack-bookmarks.sh list   <channel_id>
  slack-bookmarks.sh add    <channel_id> <title> <url>
  slack-bookmarks.sh edit   <channel_id> <bookmark_id> <title> <url>
  slack-bookmarks.sh remove <channel_id> <bookmark_id>
USAGE
  exit 1
}

post_json() {
  # $1 = method name, $2 = JSON body
  curl -fsS -X POST "https://slack.com/api/$1" \
    -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
    -H 'Content-Type: application/json; charset=utf-8' \
    --data "$2"
}

cmd="${1:-}"
shift || true

case "$cmd" in
  list)
    [[ $# -eq 1 ]] || usage
    channel="$1"
    resp=$(post_json bookmarks.list \
      "$(jq -n --arg channel_id "$channel" '{channel_id:$channel_id}')")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  add)
    [[ $# -eq 3 ]] || usage
    channel="$1"; title="$2"; url="$3"
    resp=$(post_json bookmarks.add \
      "$(jq -n --arg channel_id "$channel" --arg title "$title" --arg link "$url" \
        '{channel_id:$channel_id, title:$title, type:"link", link:$link}')")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  edit)
    [[ $# -eq 4 ]] || usage
    channel="$1"; bookmark_id="$2"; title="$3"; url="$4"
    resp=$(post_json bookmarks.edit \
      "$(jq -n --arg channel_id "$channel" --arg bookmark_id "$bookmark_id" --arg title "$title" --arg link "$url" \
        '{channel_id:$channel_id, bookmark_id:$bookmark_id, title:$title, link:$link}')")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  remove)
    [[ $# -eq 2 ]] || usage
    channel="$1"; bookmark_id="$2"
    resp=$(post_json bookmarks.remove \
      "$(jq -n --arg channel_id "$channel" --arg bookmark_id "$bookmark_id" \
        '{channel_id:$channel_id, bookmark_id:$bookmark_id}')")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  *)
    usage
    ;;
esac

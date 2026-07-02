#!/usr/bin/env bash
set -euo pipefail

# Slack 채널 관리 — claude_ai Slack MCP 도구셋엔 채널 생성/보관/이름변경/토픽·목적 설정/초대/추방/읽음처리가 없어
# xoxp(user) 토큰으로 Slack Web API(conversations.*)를 직접 호출한다.
#
# 모든 서브커맨드가 공유된 워크스페이스 상태(다른 사람에게도 보이는)를 변경한다.
# 특히 archive/kick 은 되돌리기 어렵다 — 호출 전 반드시 사용자 확인을 받을 것 (SKILL.md 참고).
#
# Usage:
#   slack-channel-admin.sh whoami
#   slack-channel-admin.sh create <name> [private]
#   slack-channel-admin.sh archive <channel>
#   slack-channel-admin.sh rename <channel> <new_name>
#   slack-channel-admin.sh set-topic <channel> <topic>
#   slack-channel-admin.sh set-purpose <channel> <purpose>
#   slack-channel-admin.sh invite <channel> <user_id_csv>
#   slack-channel-admin.sh kick <channel> <user_id>
#   slack-channel-admin.sh mark-read <channel> <ts>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SLACK_CHANNEL_ADMIN_ENV:-}"
if [[ -z "$ENV_FILE" ]]; then
  for candidate in "$HOME/.config/slack-user-token/.env" "$HOME/.config/slack-channel-admin/.env" "$SCRIPT_DIR/.env"; do
    [[ -f "$candidate" ]] && { ENV_FILE="$candidate"; break; }
  done
fi
[[ -f "$ENV_FILE" ]] || { echo "ERROR: .env not found. Tried SLACK_CHANNEL_ADMIN_ENV, ~/.config/slack-user-token/.env, ~/.config/slack-channel-admin/.env, ${SCRIPT_DIR}/.env" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${SLACK_USER_TOKEN:?SLACK_USER_TOKEN (xoxp-...) required in .env}"

usage() {
  cat <<'USAGE' >&2
Usage:
  slack-channel-admin.sh whoami
  slack-channel-admin.sh create <name> [private]
  slack-channel-admin.sh archive <channel>
  slack-channel-admin.sh rename <channel> <new_name>
  slack-channel-admin.sh set-topic <channel> <topic>
  slack-channel-admin.sh set-purpose <channel> <purpose>
  slack-channel-admin.sh invite <channel> <user_id_csv>
  slack-channel-admin.sh kick <channel> <user_id>
  slack-channel-admin.sh mark-read <channel> <ts>
USAGE
  exit 1
}

# call <slack_method> <json_body>
call() {
  local method="$1" body="$2" resp
  resp=$(curl -fsS -X POST "https://slack.com/api/${method}" \
    -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
    -H 'Content-Type: application/json; charset=utf-8' \
    --data "$body")
  echo "$resp"
  [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
}

cmd="${1:-}"
shift || true

case "$cmd" in
  whoami)
    curl -fsS -X POST https://slack.com/api/auth.test \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}"
    echo
    ;;

  create)
    [[ $# -eq 1 || $# -eq 2 ]] || usage
    name="$1"
    is_private=false
    [[ "${2:-}" == "private" ]] && is_private=true
    call conversations.create \
      "$(jq -n --arg name "$name" --argjson is_private "$is_private" \
        '{name:$name, is_private:$is_private}')"
    ;;

  archive)
    [[ $# -eq 1 ]] || usage
    channel="$1"
    call conversations.archive \
      "$(jq -n --arg channel "$channel" '{channel:$channel}')"
    ;;

  rename)
    [[ $# -eq 2 ]] || usage
    channel="$1"; new_name="$2"
    call conversations.rename \
      "$(jq -n --arg channel "$channel" --arg name "$new_name" \
        '{channel:$channel, name:$name}')"
    ;;

  set-topic)
    [[ $# -eq 2 ]] || usage
    channel="$1"; topic="$2"
    call conversations.setTopic \
      "$(jq -n --arg channel "$channel" --arg topic "$topic" \
        '{channel:$channel, topic:$topic}')"
    ;;

  set-purpose)
    [[ $# -eq 2 ]] || usage
    channel="$1"; purpose="$2"
    call conversations.setPurpose \
      "$(jq -n --arg channel "$channel" --arg purpose "$purpose" \
        '{channel:$channel, purpose:$purpose}')"
    ;;

  invite)
    [[ $# -eq 2 ]] || usage
    channel="$1"; users="$2"
    call conversations.invite \
      "$(jq -n --arg channel "$channel" --arg users "$users" \
        '{channel:$channel, users:$users}')"
    ;;

  kick)
    [[ $# -eq 2 ]] || usage
    channel="$1"; user="$2"
    call conversations.kick \
      "$(jq -n --arg channel "$channel" --arg user "$user" \
        '{channel:$channel, user:$user}')"
    ;;

  mark-read)
    [[ $# -eq 2 ]] || usage
    channel="$1"; ts="$2"
    call conversations.mark \
      "$(jq -n --arg channel "$channel" --arg ts "$ts" \
        '{channel:$channel, ts:$ts}')"
    ;;

  *)
    usage
    ;;
esac

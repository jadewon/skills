#!/usr/bin/env bash
set -euo pipefail

# Slack 내 상태메시지/프레즌스 설정 — claude_ai Slack MCP 도구셋엔 users.profile.set/
# users.setPresence 가 없어 xoxp(user) 토큰으로 Slack Web API 를 직접 호출한다.
# 내 계정의 상태·프레즌스 배지는 워크스페이스 전체에 보이므로 실행 전 사용자 확인 필요.
#
# Usage:
#   slack-status.sh set-status <text> <emoji> [expiration_unix]
#   slack-status.sh clear-status
#   slack-status.sh presence <auto|away>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SLACK_STATUS_ENV:-}"
if [[ -z "$ENV_FILE" ]]; then
  for candidate in "$HOME/.config/slack-user-token/.env" "$HOME/.config/slack-status/.env" "$SCRIPT_DIR/.env"; do
    [[ -f "$candidate" ]] && { ENV_FILE="$candidate"; break; }
  done
fi
[[ -f "$ENV_FILE" ]] || { echo "ERROR: .env not found. Tried SLACK_STATUS_ENV, ~/.config/slack-user-token/.env, ~/.config/slack-status/.env, ${SCRIPT_DIR}/.env" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${SLACK_USER_TOKEN:?SLACK_USER_TOKEN (xoxp-...) required in .env}"

usage() {
  cat <<'USAGE' >&2
Usage:
  slack-status.sh set-status <text> <emoji> [expiration_unix]
  slack-status.sh clear-status
  slack-status.sh presence <auto|away>
USAGE
  exit 1
}

profile_set() {
  local text="$1" emoji="$2" exp="$3"
  local resp
  resp=$(curl -fsS -X POST https://slack.com/api/users.profile.set \
    -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
    -H 'Content-Type: application/json; charset=utf-8' \
    --data "$(jq -n --arg t "$text" --arg e "$emoji" --argjson exp "$exp" \
      '{profile: {status_text:$t, status_emoji:$e, status_expiration:$exp}}')")
  echo "$resp"
  [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
}

cmd="${1:-}"
shift || true

case "$cmd" in
  set-status)
    [[ $# -eq 2 || $# -eq 3 ]] || usage
    exp="${3:-0}"
    [[ "$exp" =~ ^[0-9]+$ ]] || usage
    profile_set "$1" "$2" "$exp"
    ;;

  clear-status)
    [[ $# -eq 0 ]] || usage
    profile_set "" "" 0
    ;;

  presence)
    [[ $# -eq 1 ]] || usage
    case "$1" in
      auto|away) ;;
      *) usage ;;
    esac
    resp=$(curl -fsS -X POST https://slack.com/api/users.setPresence \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      -H 'Content-Type: application/json; charset=utf-8' \
      --data "$(jq -n --arg p "$1" '{presence:$p}')")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  *)
    usage
    ;;
esac

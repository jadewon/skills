#!/usr/bin/env bash
set -euo pipefail

# Slack 자체 리마인더 — claude_ai Slack MCP 도구셋엔 reminders.* 가 없어
# xoxp(user) 토큰으로 Slack Web API 를 직접 호출한다. 리마인더는 토큰 소유자
# 본인 것만 생성/조회/완료/삭제된다 (Slack 정책상 다른 사용자 대상 설정 불가).
#
# Usage:
#   slack-reminders.sh add <text> <time>
#   slack-reminders.sh list
#   slack-reminders.sh complete <reminder_id>
#   slack-reminders.sh delete <reminder_id>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SLACK_REMINDERS_ENV:-}"
if [[ -z "$ENV_FILE" ]]; then
  for candidate in "$HOME/.config/slack-user-token/.env" "$HOME/.config/slack-reminders/.env" "$SCRIPT_DIR/.env"; do
    [[ -f "$candidate" ]] && { ENV_FILE="$candidate"; break; }
  done
fi
[[ -f "$ENV_FILE" ]] || { echo "ERROR: .env not found. Tried SLACK_REMINDERS_ENV, ~/.config/slack-user-token/.env, ~/.config/slack-reminders/.env, ${SCRIPT_DIR}/.env" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${SLACK_USER_TOKEN:?SLACK_USER_TOKEN (xoxp-...) required in .env}"

usage() {
  cat <<'USAGE' >&2
Usage:
  slack-reminders.sh add <text> <time>     # time: "in 15 minutes" | "tomorrow at 9am" | "every Thursday" | Unix timestamp
  slack-reminders.sh list                   # 내 리마인더 목록 (id/text/time)
  slack-reminders.sh complete <reminder_id> # 완료 처리 (id 예: Rm12345678)
  slack-reminders.sh delete <reminder_id>   # 삭제 (id 예: Rm12345678)
USAGE
  exit 1
}

cmd="${1:-}"
shift || true

case "$cmd" in
  add)
    [[ $# -eq 2 ]] || usage
    text="$1"; time="$2"
    resp=$(curl -fsS -X POST https://slack.com/api/reminders.add \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      -H 'Content-Type: application/json; charset=utf-8' \
      --data "$(jq -n --arg text "$text" --arg time "$time" \
        '{text:$text, time:$time}')")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  list)
    [[ $# -eq 0 ]] || usage
    resp=$(curl -fsS https://slack.com/api/reminders.list \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  complete)
    [[ $# -eq 1 ]] || usage
    reminder="$1"
    resp=$(curl -fsS -X POST https://slack.com/api/reminders.complete \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      -H 'Content-Type: application/json; charset=utf-8' \
      --data "$(jq -n --arg reminder "$reminder" '{reminder:$reminder}')")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  delete)
    [[ $# -eq 1 ]] || usage
    reminder="$1"
    resp=$(curl -fsS -X POST https://slack.com/api/reminders.delete \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      -H 'Content-Type: application/json; charset=utf-8' \
      --data "$(jq -n --arg reminder "$reminder" '{reminder:$reminder}')")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  *)
    usage
    ;;
esac

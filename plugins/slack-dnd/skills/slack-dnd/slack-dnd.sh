#!/usr/bin/env bash
set -euo pipefail

# Slack 방해금지(Do Not Disturb) 제어 — claude_ai Slack MCP 도구셋엔 DND 관련 도구가 없어
# xoxp(user) 토큰으로 Slack Web API 를 직접 호출한다. snooze/end-snooze 는 본인 계정의
# 실제 알림 상태를 바꾸므로 반드시 본인 user 토큰을 쓴다.
#
# Usage:
#   slack-dnd.sh snooze <minutes>
#   slack-dnd.sh end-snooze
#   slack-dnd.sh info [user_id]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SLACK_DND_ENV:-}"
if [[ -z "$ENV_FILE" ]]; then
  for candidate in "$HOME/.config/slack-user-token/.env" "$HOME/.config/slack-dnd/.env" "$SCRIPT_DIR/.env"; do
    [[ -f "$candidate" ]] && { ENV_FILE="$candidate"; break; }
  done
fi
[[ -f "$ENV_FILE" ]] || { echo "ERROR: .env not found. Tried SLACK_DND_ENV, ~/.config/slack-user-token/.env, ~/.config/slack-dnd/.env, ${SCRIPT_DIR}/.env" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${SLACK_USER_TOKEN:?SLACK_USER_TOKEN (xoxp-...) required in .env}"

usage() {
  cat <<'USAGE' >&2
Usage:
  slack-dnd.sh snooze <minutes>
  slack-dnd.sh end-snooze
  slack-dnd.sh info [user_id]
USAGE
  exit 1
}

cmd="${1:-}"
shift || true

case "$cmd" in
  snooze)
    [[ $# -eq 1 ]] || usage
    [[ "$1" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: <minutes> must be a positive integer, got: $1" >&2; usage; }
    minutes="$1"
    resp=$(curl -fsS -X POST https://slack.com/api/dnd.setSnooze \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      -H 'Content-Type: application/json; charset=utf-8' \
      --data "$(jq -n --argjson n "$minutes" '{num_minutes:$n}')")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  end-snooze)
    [[ $# -eq 0 ]] || usage
    resp=$(curl -fsS -X POST https://slack.com/api/dnd.endSnooze \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  info)
    [[ $# -le 1 ]] || usage
    if [[ $# -eq 1 ]]; then
      resp=$(curl -fsS -G https://slack.com/api/dnd.info \
        -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
        --data-urlencode "user=$1")
    else
      resp=$(curl -fsS -G https://slack.com/api/dnd.info \
        -H "Authorization: Bearer ${SLACK_USER_TOKEN}")
    fi
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  *)
    usage
    ;;
esac

#!/usr/bin/env bash
set -euo pipefail

# Slack 유저그룹(@-멘션 가능한 커스텀 그룹) 관리 — claude_ai Slack MCP 도구셋엔
# usergroups.* 가 없어 xoxp(user) 토큰으로 Slack Web API 를 직접 호출한다.
# 필요 스코프: usergroups:write (User Token Scopes). 워크스페이스 설정에서
# 유저그룹 관리 권한이 관리자에게만 열려 있으면 permission_denied 가 날 수 있다.
#
# Usage:
#   slack-usergroups.sh create <name> [handle]
#   slack-usergroups.sh update <usergroup_id> [name] [handle]
#   slack-usergroups.sh set-users <usergroup_id> <user_id_csv>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SLACK_USERGROUPS_ENV:-}"
if [[ -z "$ENV_FILE" ]]; then
  for candidate in "$HOME/.config/slack-user-token/.env" "$HOME/.config/slack-usergroups/.env" "$SCRIPT_DIR/.env"; do
    [[ -f "$candidate" ]] && { ENV_FILE="$candidate"; break; }
  done
fi
[[ -f "$ENV_FILE" ]] || { echo "ERROR: .env not found. Tried SLACK_USERGROUPS_ENV, ~/.config/slack-user-token/.env, ~/.config/slack-usergroups/.env, ${SCRIPT_DIR}/.env" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${SLACK_USER_TOKEN:?SLACK_USER_TOKEN (xoxp-...) required in .env}"

usage() {
  cat <<'USAGE' >&2
Usage:
  slack-usergroups.sh create <name> [handle]
  slack-usergroups.sh update <usergroup_id> [name] [handle]
  slack-usergroups.sh set-users <usergroup_id> <user_id_csv>

  create      새 유저그룹 생성. handle 은 @멘션용 짧은 이름(생략 가능).
  update      이름/핸들 변경. 넘긴 필드만 갱신하고, 생략한 필드는 그대로 둔다.
  set-users   멤버십을 user_id_csv(쉼표구분 U... 아이디)로 통째로 교체한다.
              — 추가가 아니라 REPLACE 다. 넘긴 목록이 곧 전체 멤버가 된다.
USAGE
  exit 1
}

cmd="${1:-}"
shift || true

case "$cmd" in
  create)
    [[ $# -eq 1 || $# -eq 2 ]] || usage
    name="$1"
    if [[ $# -eq 2 ]]; then
      body=$(jq -n --arg name "$name" --arg handle "$2" '{name:$name, handle:$handle}')
    else
      body=$(jq -n --arg name "$name" '{name:$name}')
    fi
    resp=$(curl -fsS -X POST https://slack.com/api/usergroups.create \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      -H 'Content-Type: application/json; charset=utf-8' \
      --data "$body")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  update)
    [[ $# -ge 1 && $# -le 3 ]] || usage
    usergroup="$1"
    body=$(jq -n --arg usergroup "$usergroup" '{usergroup:$usergroup}')
    # 넘긴 필드만 추가 — 생략한 필드는 빈 값으로 덮어쓰지 않는다.
    if [[ $# -ge 2 && -n "${2:-}" ]]; then
      body=$(echo "$body" | jq --arg name "$2" '. + {name:$name}')
    fi
    if [[ $# -ge 3 && -n "${3:-}" ]]; then
      body=$(echo "$body" | jq --arg handle "$3" '. + {handle:$handle}')
    fi
    resp=$(curl -fsS -X POST https://slack.com/api/usergroups.update \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      -H 'Content-Type: application/json; charset=utf-8' \
      --data "$body")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  set-users)
    [[ $# -eq 2 ]] || usage
    usergroup="$1"; users="$2"
    # 주의: users 는 멤버십을 REPLACE 한다 (추가 아님). 넘긴 CSV 가 전체 멤버가 됨.
    resp=$(curl -fsS -X POST https://slack.com/api/usergroups.users.update \
      -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
      -H 'Content-Type: application/json; charset=utf-8' \
      --data "$(jq -n --arg usergroup "$usergroup" --arg users "$users" \
        '{usergroup:$usergroup, users:$users}')")
    echo "$resp"
    [[ "$(echo "$resp" | jq -r '.ok')" == "true" ]] || exit 2
    ;;

  *)
    usage
    ;;
esac

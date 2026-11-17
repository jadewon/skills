#!/usr/bin/env bash
# dog-recent.sh — 채널에 이미 올린 최근 댕댕이 사진 코멘트를 출력한다 (봇 토큰, 읽기 전용).
#
# 스킬은 매일 새로 실행되어 어제 무슨 말을 썼는지 모른다. 그대로 두면 같은 표현이 반복된다.
# SKILL.md 가 코멘트를 쓰기 전에 호출해서 최근에 쓴 표현을 피하는 데 쓴다.
# .env 는 dog-post.sh 와 같다 (~/.config/dog-daily/.env).
#
# usage: dog-recent.sh [개수]   (기본 7)
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

COUNT="${1:-7}"

# limit=60 으로 넉넉히 받아 사진 글만 걸러낸다 — 같은 채널에 dog-fact-daily 글도 섞인다.
RESP=$(curl -sS --max-time 10 --get https://slack.com/api/conversations.history \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  --data-urlencode "channel=$SLACK_CHANNEL" \
  --data-urlencode "limit=60")

echo "$RESP" | COUNT="$COUNT" python3 -c '
import json, os, sys
d = json.load(sys.stdin)
if not d.get("ok"):
    print("ERROR: Slack rejected: %s" % d.get("error"), file=sys.stderr)
    sys.exit(3)
# 사진 글 판별: 사진을 파일로 올리므로 files 가 있다. 같은 채널의 dog-fact-daily 글은 파일이 없다.
lines = [m["text"].split("\n")[0].strip()
         for m in d.get("messages", [])
         if m.get("files")]
for line in lines[:int(os.environ["COUNT"])]:
    print(line)
'

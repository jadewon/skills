#!/usr/bin/env bash
set -euo pipefail

# CNN Fear & Greed Index 일일 리포팅 → Slack (incoming webhook)
# Usage: fearandgreed.sh [YYYY-MM-DD]   (날짜 생략 시 오늘)
#
# webhook 은 .env 의 SLACK_WEBHOOK_URL 에서 로드한다 — jadewon/skills 는 PUBLIC 이라
# 시크릿을 스크립트에 박지 않는다. .env.example 참고.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${FEARANDGREED_ENV:-}"
if [[ -z "$ENV_FILE" ]]; then
  for candidate in "$HOME/.config/fearandgreed/.env" "$SCRIPT_DIR/.env"; do
    [[ -f "$candidate" ]] && { ENV_FILE="$candidate"; break; }
  done
fi
[[ -f "$ENV_FILE" ]] || { echo "ERROR: .env not found. Tried FEARANDGREED_ENV, ~/.config/fearandgreed/.env, ${SCRIPT_DIR}/.env" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${SLACK_WEBHOOK_URL:?SLACK_WEBHOOK_URL required in .env}"

DATE="${1:-$(date +%Y-%m-%d)}"

# 공휴일 스킵 (hiworks) — 한국 공휴일이면 게시하지 않는다. .env 의 HOLIDAY_API_URL 로 override 가능.
HOLIDAY_API_URL="${HOLIDAY_API_URL:-https://hiworks-production.up.railway.app/hiworks/holiday}"
hol=$(curl -s --max-time 10 "${HOLIDAY_API_URL}?startDate=${DATE}&endDate=${DATE}" || echo "[]")
if [[ "$hol" != "[]" ]]; then
  echo "공휴일 스킵: $DATE"
  exit 0
fi

API="https://production.dataviz.cnn.io/index/fearandgreed/graphdata/${DATE}"

# --- fetch ---------------------------------------------------------------
resp=$(curl -fsS "$API" \
  -H 'origin: https://edition.cnn.com' \
  -H 'user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36')

fg=$(echo "$resp" | jq '.fear_and_greed')

score=$(echo "$fg" | jq -r '.score')
rating=$(echo "$fg" | jq -r '.rating')
prev_close=$(echo "$fg" | jq -r '.previous_close')
prev_week=$(echo "$fg"  | jq -r '.previous_1_week')
prev_month=$(echo "$fg" | jq -r '.previous_1_month')
prev_year=$(echo "$fg"  | jq -r '.previous_1_year')

if [[ "$score" == "null" || -z "$score" ]]; then
  echo "데이터 없음: $DATE" >&2
  exit 1
fi

# --- presentation --------------------------------------------------------
case "$rating" in
  "extreme fear")  emoji="😱"; label="Extreme Fear"  ;;
  "fear")          emoji="😨"; label="Fear"          ;;
  "neutral")       emoji="😐"; label="Neutral"       ;;
  "greed")         emoji="🤑"; label="Greed"         ;;
  "extreme greed") emoji="🚀"; label="Extreme Greed" ;;
  *)               emoji="📊"; label="$rating"       ;;
esac

score_int=$(printf '%.0f' "$score")

# 0-100 → 10칸 게이지
filled=$(( score_int / 10 ))
(( filled > 10 )) && filled=10
(( filled < 0  )) && filled=0
empty=$(( 10 - filled ))
bar=""
for ((i=0; i<filled; i++)); do bar+="▰"; done
for ((i=0; i<empty;  i++)); do bar+="▱"; done

# 전일 종가 대비 변화
delta=$(awk -v a="$score" -v b="$prev_close" 'BEGIN{printf "%.2f", a-b}')
arrow=$(awk -v d="$delta" 'BEGIN{ if(d>0) print "▲"; else if(d<0) print "▼"; else print "▬"}')
delta_abs=$(awk -v d="$delta" 'BEGIN{printf "%.2f", (d<0?-d:d)}')

table=$(printf '%-11s %6.2f  %s %s\n%-11s %6.2f\n%-11s %6.2f\n%-11s %6.2f' \
  "Prev close" "$prev_close" "$arrow" "$delta_abs" \
  "1 week"     "$prev_week" \
  "1 month"    "$prev_month" \
  "1 year"     "$prev_year")

text=$(cat <<EOF
:chart_with_upwards_trend: *CNN Fear & Greed Index*  \`${DATE}\`

${emoji} *${score_int}* · ${label}
\`${bar}\`  ${score_int}/100

\`\`\`
${table}
\`\`\`
EOF
)

# --- send ----------------------------------------------------------------
payload=$(jq -n --arg text "$text" \
  '{text:$text, username:"Fear & Greed", icon_emoji:":chart_with_upwards_trend:", mrkdwn:true}')

curl -fsS -X POST \
  -H 'Content-Type: application/json' \
  --data "$payload" \
  "$SLACK_WEBHOOK_URL"
echo

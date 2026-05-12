#!/bin/bash
# weather-daily.sh — helper for the weather-daily Claude Code skill.
# Deterministic parts (API fetch, aggregation, Slack send) live here so the SKILL.md
# stays short and the model is not regenerating the same bash on every invocation.
#
# Subcommands:
#   holiday          → prints "true" / "false". exits 0.
#   fetch            → prints aggregated JSON to stdout.
#   send <message>   → POST to Slack incoming webhook.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${WEATHER_DAILY_ENV:-}"
if [[ -z "$ENV_FILE" ]]; then
  for candidate in "$HOME/.config/weather-daily/.env" "$SCRIPT_DIR/.env"; do
    [[ -f "$candidate" ]] && { ENV_FILE="$candidate"; break; }
  done
fi
[[ -f "$ENV_FILE" ]] || { echo "ERROR: .env not found. Tried WEATHER_DAILY_ENV, ~/.config/weather-daily/.env, ${SCRIPT_DIR}/.env" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${KMA_SERVICE_KEY:?KMA_SERVICE_KEY required in .env}"
: "${SLACK_WEBHOOK_URL:?SLACK_WEBHOOK_URL required in .env}"
NX="${NX:-60}"
NY="${NY:-127}"
AREA_NO="${AREA_NO:-1114000000}"
HOLIDAY_API_URL="${HOLIDAY_API_URL:-}"

TMP="${TMPDIR:-/tmp}/weather-daily-$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

cmd="${1:-}"
shift || true

case "$cmd" in
  holiday)
    if [[ -z "$HOLIDAY_API_URL" ]]; then
      echo "false"
      exit 0
    fi
    DATE=$(date +%Y-%m-%d)
    RESP=$(curl -sS --max-time 10 "${HOLIDAY_API_URL}?startDate=${DATE}&endDate=${DATE}" || echo "[]")
    if [[ "$RESP" == "[]" ]]; then echo "false"; else echo "true"; fi
    ;;

  fetch)
    YMD=$(date +%Y%m%d)
    DASH=$(date +%Y-%m-%d)

    curl -sS --max-time 15 \
      "http://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getVilageFcst?pageNo=1&numOfRows=300&dataType=JSON&base_date=${YMD}&base_time=0500&nx=${NX}&ny=${NY}&serviceKey=${KMA_SERVICE_KEY}" \
      > "$TMP/fcst.json"
    curl -sS --max-time 15 \
      "http://apis.data.go.kr/B552584/ArpltnInforInqireSvc/getMinuDustFrcstDspth?searchDate=${DASH}&informCode=PM10&pageNo=1&numOfRows=1&returnType=json&serviceKey=${KMA_SERVICE_KEY}" \
      > "$TMP/pm10.json"
    curl -sS --max-time 15 \
      "http://apis.data.go.kr/B552584/ArpltnInforInqireSvc/getMinuDustFrcstDspth?searchDate=${DASH}&informCode=PM25&pageNo=1&numOfRows=1&returnType=json&serviceKey=${KMA_SERVICE_KEY}" \
      > "$TMP/pm25.json"
    curl -sS --max-time 15 \
      "http://apis.data.go.kr/1360000/LivingWthrIdxServiceV4/getUVIdxV4?areaNo=${AREA_NO}&time=${YMD}06&dataType=JSON&serviceKey=${KMA_SERVICE_KEY}" \
      > "$TMP/uv.json"

    YMD="$YMD" TMP_DIR="$TMP" python3 <<'PYEOF'
import json, math, os, sys
from collections import defaultdict

YMD = os.environ['YMD']
T = os.environ['TMP_DIR']

try:
    fcst = json.load(open(f'{T}/fcst.json'))['response']['body']['items']['item']
except Exception as e:
    print(f'ERROR: failed to parse forecast: {e}', file=sys.stderr)
    sys.exit(2)

by_time = defaultdict(dict)
for i in fcst:
    if i['fcstDate'] == YMD:
        by_time[i['fcstTime']][i['category']] = i['fcstValue']

def feel(t, v_ms, rh):
    v_kmh = v_ms * 3.6
    if t <= 10 and v_kmh >= 4.8:
        return 13.12 + 0.6215*t - 11.37*(v_kmh**0.16) + 0.3965*(v_kmh**0.16)*t
    if t >= 27 and rh >= 40:
        tw = (t * math.atan(0.151977*((rh+8.313659)**0.5))
              + math.atan(t+rh) - math.atan(rh-1.67633)
              + 0.00391838*(rh**1.5)*math.atan(0.023101*rh)
              - 4.686035)
        return -0.2442 + 0.55399*tw + 0.45535*t - 0.0022*tw*tw + 0.00278*tw*t + 3
    return t

tmps, feels, rain = [], [], []
wmax = 0.0
for tt in sorted(by_time.keys()):
    d = by_time[tt]
    if 'TMP' not in d:
        continue
    t  = float(d['TMP'])
    v  = float(d.get('WSD', 0))
    rh = float(d.get('REH', 50))
    tmps.append(t)
    feels.append(feel(t, v, rh))
    wmax = max(wmax, v)
    pop = int(d.get('POP', 0))
    pty = int(d.get('PTY', 0))   # 0없음 1비 2비눈 3눈 4소나기
    pcp = d.get('PCP', '강수없음')
    if pty != 0 or pop >= 30 or pcp not in ('강수없음', '0'):
        rain.append({'time': tt, 'pop': pop, 'pty': pty, 'pcp': pcp})

def grade_seoul(path):
    try:
        items = json.load(open(path))['response']['body']['items']
        for chunk in items[0]['informGrade'].split(','):
            if chunk.strip().startswith('서울'):
                return chunk.split(':')[1].strip()
    except Exception:
        return None
    return None

pm10 = grade_seoul(f'{T}/pm10.json')
pm25 = grade_seoul(f'{T}/pm25.json')

try:
    uv = json.load(open(f'{T}/uv.json'))['response']['body']['items']['item'][0]
    uv_max = max(int(uv.get(f'h{h}', 0) or 0) for h in (0, 3, 6, 9, 12))
except Exception:
    uv_max = 0

print(json.dumps({
    'date': YMD,
    'tmin': round(min(tmps), 1) if tmps else None,
    'tmax': round(max(tmps), 1) if tmps else None,
    'feel_min': round(min(feels), 1) if feels else None,
    'feel_max': round(max(feels), 1) if feels else None,
    'diurnal': round(max(tmps) - min(tmps), 1) if tmps else 0,
    'wind_max': round(wmax, 1),
    'rain_hours': rain,
    'pm10_seoul': pm10,
    'pm25_seoul': pm25,
    'uv_max_today': uv_max,
}, ensure_ascii=False, indent=2))
PYEOF
    ;;

  send)
    MSG="${1:?usage: $0 send <message>}"
    RESP=$(curl -sS --max-time 10 -X POST "$SLACK_WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      --data "$(jq -n --arg text "$MSG" '{text: $text}')")
    if [[ "$RESP" != "ok" ]]; then
      echo "ERROR: Slack rejected: $RESP" >&2
      exit 3
    fi
    echo "ok"
    ;;

  *)
    cat >&2 <<USAGE
Usage:
  $0 holiday          → "true" / "false"
  $0 fetch            → aggregated JSON (stdout)
  $0 send <message>   → POST to Slack webhook
USAGE
    exit 1
    ;;
esac

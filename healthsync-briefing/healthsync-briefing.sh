#!/bin/bash
# HealthSync briefing data fetcher.
# fetch [days]: pull the last N daily snapshots from jadewon/health (GitHub
# Contents API via authed gh CLI) and emit one compact JSON to stdout.
# Missing days (never synced) are listed in "gaps".
set -euo pipefail

case "${1:-}" in
  fetch)
    python3 - "${2:-7}" <<'PY'
import base64, datetime, json, subprocess, sys

days = int(sys.argv[1])
today = datetime.date.today()
out = {"generated_for": today.isoformat(), "days": [], "gaps": []}

for i in range(days - 1, -1, -1):
    d = today - datetime.timedelta(days=i)
    path = f"data/{d.year}/{d.month:02d}/{d.isoformat()}.json"
    r = subprocess.run(
        ["gh", "api", f"repos/jadewon/health/contents/{path}", "--jq", ".content"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        # 404 = this day was never synced (a real finding). Any other
        # failure (auth expiry, rate limit, network, 5xx) must NOT be
        # silently misread as a data gap — surface it and stop.
        if "404" in r.stderr:
            out["gaps"].append(d.isoformat())
            continue
        sys.exit(f"gh api failed for {d.isoformat()}: {r.stderr.strip()}")
    try:
        doc = json.loads(base64.b64decode(r.stdout.strip()))
    except ValueError as e:
        sys.exit(f"corrupt snapshot for {d.isoformat()}: {e}")
    present = {}
    for key, metric in doc.get("metrics", {}).items():
        if metric.get("present"):
            present[key] = {
                k: v for k, v in metric.items()
                if v is not None and k in ("value", "avg", "min", "max", "count", "sources")
            }
    out["days"].append({
        "date": doc.get("date"),
        "metrics": present,
        "sleep": doc.get("sleep"),
        "workouts": doc.get("workouts", []),
        "scores": doc.get("scores"),
        "missing_count": len(doc.get("missing", [])),
    })

print(json.dumps(out, ensure_ascii=False))
PY
    ;;
  *)
    echo "usage: healthsync-briefing.sh fetch [days]" >&2
    exit 1
    ;;
esac

---
name: healthsync-briefing
description: HealthSync가 GitHub(jadewon/health)에 쌓는 일일 건강 데이터를 읽어 AI 해석 브리핑(회복·수면·활동·특이사항 + 행동 제안)을 생성한다. "건강 브리핑", "요즘 몸 어때" 류 요청 시 사용.
allowed-tools: Bash
---

# HealthSync Briefing

The interpretation layer of the HealthSync pipeline (iPhone app → `jadewon/health` repo → this briefing). The app is a dumb collector; ALL interpretation happens here. Reference class: Bevel Intelligence / Vora — recovery reading + actionable day guidance, not a stats dump.

## Hard rules

- **Numbers appear once, in their claim.** Never re-list raw data the user can read in the repo. A mechanical stats table is NOT analysis (proven feedback) — every number cited must carry an interpretation or an action.
- **No fabrication, no diagnosis.** Only metrics present in the fetched JSON. Absolute-value physiology claims (e.g. "HRV 19ms is low") must be hedged until a personal baseline exists (7+ watch days). This is lifestyle guidance, not medical advice — say so only when a finding is health-critical (e.g. sustained SpO2 < 92, resting HR trend +10bpm), and then recommend a doctor, calmly.
- **Gaps are findings.** No-watch days (`missing_count` high) and `gaps` (never-synced dates) shape what can be said — name them and what wearing the watch (esp. at night) would unlock. Never interpolate over them.
- **Actions: 1–3, concrete, today-sized.** ("오늘 30분 걷기", "오늘 밤 워치 차고 자기") — no habit lectures.
- Output in Korean, one screen max. Lead with the single most decision-relevant finding. No greetings, no closing filler.

## Flow

### 1. Fetch

```bash
"${CLAUDE_SKILL_DIR}/healthsync-briefing.sh" fetch 7
```

User says 2주/한달 → pass 14/30. Output: `{generated_for, days:[{date, metrics(present only), sleep, workouts, scores, missing_count}], gaps:[dates]}`. `scores` (readiness / sleep_debt_min / training_load{ctl,atl,tsb}) is computed on-device by the app; present only when the phone had enough history — prefer it over recomputing.

### 2. Interpret

Read every day, then write sections **only where there is something to say** (empty section = omit):

- **회복** — HRV(sdnn) + resting HR direction vs the window's own baseline; `scores.readiness` when present (65+ 좋음 / 40–65 보통 / 40- 부담).
- **수면** — duration + stages vs 8h; `sleep_debt_min` when present. If no sleep data at all: that IS the finding.
- **활동/부하** — steps·exercise·workouts; `training_load.tsb` negative = acute load above chronic (회복 우선), positive = 여유.
- **특이사항** — anything anomalous the data supports: noise exposure >85dBA, SpO2 dips, walking-metric shifts, unusually high all-day HR.
- **데이터 공백** — no-watch days + `gaps`, and the single habit change that fixes them.
- **오늘 할 것** — the 1–3 actions.

### 3. Deliver

Print the briefing in the conversation. Delivery elsewhere (Slack, scheduling) is intentionally NOT part of this skill — the user manages automations themselves.

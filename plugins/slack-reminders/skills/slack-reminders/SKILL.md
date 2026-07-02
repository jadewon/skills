---
name: slack-reminders
description: Slack 자체 리마인더를 생성(reminders.add)/조회(reminders.list)/완료(reminders.complete)/삭제(reminders.delete)한다. claude_ai Slack MCP 도구셋엔 reminders.* 가 없어 xoxp user 토큰으로 Slack Web API 를 직접 호출한다.
argument-hint: "<내용> <시각>으로 리마인더 걸어줘 | 내 리마인더 목록 | <리마인더> 완료/삭제해줘"
allowed-tools: Bash
---

# Slack Reminders

Slack 자체 리마인더를 만들고 관리한다. `mcp__claude_ai_Slack__*` 도구셋에는 `reminders.*` 가 없어서, xoxp(user) 토큰으로 Slack Web API 를 직접 호출하는 이 스킬이 필요하다.

로컬 `remind` 스킬과는 다르다: `remind` 는 macOS `osascript` 알림이라 그 맥에서만 뜨지만, Slack 리마인더는 기기 간 동기화되고 모바일 푸시로도 알려준다 — 대신 Slack user 토큰이 필요하다.

**주의**: 리마인더는 토큰 소유자 본인 것만 생성/조회/완료/삭제된다 (Slack 정책상 다른 사용자 대상 설정은 지원 종료).

## 서브커맨드

```bash
"${CLAUDE_SKILL_DIR}/slack-reminders.sh" add "<내용>" "<시각>"
"${CLAUDE_SKILL_DIR}/slack-reminders.sh" list
"${CLAUDE_SKILL_DIR}/slack-reminders.sh" complete <reminder_id>
"${CLAUDE_SKILL_DIR}/slack-reminders.sh" delete <reminder_id>
```

### add — 리마인더 생성

`<시각>` 은 세 형태를 받는다:
- 자연어: `in 15 minutes`, `tomorrow at 9am`, `at 3:30pm`, `on Tuesday`, `next week`, `every Thursday`
- 24시간 이내면 초 단위 정수: `20`
- Unix 타임스탬프 (최대 5년 후): `1602288000`

생성 전 확인: 만든 리마인더는 나중에 알림으로 뜨므로, 실행 전 **내용 + 시각**을 사용자에게 한 번 보여주고 진행한다.

### list — 목록 조회 (읽기 전용)

응답 `reminders[]` 각 항목의 필드:
- `id` — `Rm12345678` 형태. `complete`/`delete` 에 넣는 값이 바로 이것.
- `text` — 리마인더 내용
- `time` — 예정 시각 (Unix 타임스탬프; 반복 리마인더는 없음)
- `recurring` — 반복 여부(boolean)
- `complete_ts` — 완료 시각 (0 이면 미완료)

`complete`/`delete` 하기 전엔 먼저 `list` 로 `id ↔ text` 를 확인한다.

### complete / delete

`complete` 는 완료 표시, `delete` 는 완전 삭제(되돌릴 수 없음). 둘 다 실행 전에 **어떤 리마인더인지(해당 `text`)** 를 사용자에게 보여주고 확인받는다. `id` 는 `list` 응답에서 읽은 `Rm...` 값을 그대로 쓴다.

## 응답 해석

응답 JSON 의 `ok` 필드를 확인한다. `false` 면 `error` 값을 그대로 사용자에게 보고한다 (자주 보는 값: `missing_scope` — 스코프 미추가, `not_authed`/`invalid_auth` — 토큰 문제, `not_found` — 없는 `reminder` id, `cannot_parse` — `time` 형식을 못 읽음).

## 셋업

1. `.env.example` 을 `.env` 로 복사
2. [api.slack.com/apps](https://api.slack.com/apps) → 기존 앱(`slack-edit-message` 등과 공용) 선택하거나 Create New App → From scratch
3. OAuth & Permissions → **User Token Scopes** 에 두 개 추가:
   - `reminders:write` — add / complete / delete
   - `reminders:read` — list
4. Install to Workspace (스코프 추가 후 재설치 필요) → **User OAuth Token** (`xoxp-` 로 시작, `xoxb-` 아님) 복사해 `.env` 의 `SLACK_USER_TOKEN` 에 붙여넣기
5. `chmod +x slack-reminders.sh`

여러 Slack 스킬이 토큰을 공유하도록 `~/.config/slack-user-token/.env` 에 `SLACK_USER_TOKEN` 을 두면 이 값을 한 번만 붙여넣어도 된다 (스크립트가 그 경로를 먼저 찾는다). `.env` 는 gitignore 된다 — 토큰은 로컬에만 두고 레포(PUBLIC)에 커밋하지 않는다.

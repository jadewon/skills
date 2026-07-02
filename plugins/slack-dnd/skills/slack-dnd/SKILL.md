---
name: slack-dnd
description: 내 Slack 방해금지(Do Not Disturb) 상태를 제어한다 — 스누즈 시작(dnd.setSnooze)/해제(dnd.endSnooze)/현재 상태 조회(dnd.info). claude_ai Slack MCP 도구셋엔 DND 관련 도구가 없어 xoxp user 토큰으로 Slack Web API 를 직접 호출한다.
argument-hint: "N분 방해금지 켜줘 | 방해금지 꺼줘 | 지금 방해금지 상태 알려줘"
allowed-tools: Bash
---

# Slack Do Not Disturb

내 Slack 알림을 일정 시간 꺼두는 개인 집중시간(focus-time) 자동화. `mcp__claude_ai_Slack__*` 도구셋에는 DND 관련 도구가 없어서, xoxp(user) 토큰으로 Slack Web API 를 직접 호출하는 이 스킬이 필요하다.

**주의**: DND(스누즈)는 본인 계정의 알림 상태를 실제로 바꾼다. `.env` 에 넣는 토큰은 반드시 본인 계정의 user 토큰이어야 한다.

## 실행 전 확인

- `snooze` / `end-snooze` 는 지금 이 순간 본인의 실제 알림 상태를 바꾼다. 특히 `snooze` 는 N분 동안 알림을 실제로 무음 처리하므로, 실행 전에 반드시 사용자에게 분(minutes) 값과 함께 확인받는다.
- `info` 는 읽기 전용 조회라 확인 없이 바로 실행해도 된다.

## 실행

```bash
# N분 동안 방해금지(스누즈) 시작
"${CLAUDE_SKILL_DIR}/slack-dnd.sh" snooze <minutes>

# 스누즈 즉시 해제
"${CLAUDE_SKILL_DIR}/slack-dnd.sh" end-snooze

# 현재 DND 상태 조회 (인자 없으면 본인, user_id 주면 해당 사용자)
"${CLAUDE_SKILL_DIR}/slack-dnd.sh" info [user_id]
```

`<minutes>` 는 양의 정수여야 한다 (네트워크 호출 전에 검증하며, 아니면 usage 에러).

## 응답 해석

응답 JSON 의 `ok` 필드를 확인한다. `false` 면 `error` 값을 그대로 사용자에게 보고한다 (자주 보는 값: `not_authed`, `invalid_auth`, `missing_scope`, `snooze_end_failed`).

- `snooze`: `snooze_enabled`(true), `snooze_endtime`(스누즈 종료 Unix 시각), `snooze_remaining`(남은 초)
- `info`: `dnd_enabled`(스케줄된 DND 활성 여부), `next_dnd_start_ts`/`next_dnd_end_ts`(다음 DND 구간 Unix 시각), 그리고 본인 조회일 때만 `snooze_enabled`/`snooze_endtime`/`snooze_remaining`

Unix 시각은 사용자에게 보고할 때 사람이 읽을 수 있는 로컬 시각으로 변환해 알려준다.

## 셋업

1. `.env.example` 을 `.env` 로 복사
2. `slack-edit-message` 와 **같은 Slack App** 을 쓴다 ([api.slack.com/apps](https://api.slack.com/apps)). 그 앱의 OAuth & Permissions → **User Token Scopes** 에 아래 스코프를 추가:
   - `dnd:write` — `dnd.setSnooze` / `dnd.endSnooze` (스누즈 시작·해제)
   - `dnd:read` — `dnd.info` (상태 조회)
3. 스코프 추가 후 Reinstall to Workspace → **User OAuth Token** (`xoxp-` 로 시작, `xoxb-` 아님) 복사
4. 토큰은 여러 Slack 스킬이 공유하는 `~/.config/slack-user-token/.env` 의 `SLACK_USER_TOKEN` 에 붙여넣으면 이 스킬도 자동으로 읽는다 (스킬별 `.env` 를 따로 두지 않아도 됨)
5. `chmod +x slack-dnd.sh`
6. 확인: `"${CLAUDE_SKILL_DIR}/slack-dnd.sh" info` → `ok:true` 가 나오면 정상

`.env` 는 gitignore 된다 — 토큰은 로컬에만 두고 레포(PUBLIC)에 커밋하지 않는다.

---
name: slack-status
description: 내 Slack 상태메시지(users.profile.set)와 프레즌스(users.setPresence)를 설정/해제한다. claude_ai Slack MCP 도구셋엔 내 상태·프레즌스를 바꾸는 도구가 없어 xoxp user 토큰으로 Slack Web API 를 직접 호출한다.
argument-hint: "상태를 <이모지> <텍스트> 로 바꿔줘 | 상태 지워줘 | 자리비움/복귀로 바꿔줘"
allowed-tools: Bash
---

# Slack Status / Presence

내 Slack 커스텀 상태메시지와 프레즌스(활성/자리비움)를 설정하거나 해제한다. `mcp__claude_ai_Slack__*` 도구셋에는 `slack_read_user_profile`(남의 프로필 읽기)만 있고 내 상태·프레즌스를 **설정**하는 도구가 없어서, xoxp(user) 토큰으로 Slack Web API 를 직접 호출하는 이 스킬이 필요하다.

**주의**: 상태메시지·프레즌스 배지는 워크스페이스 전체에 즉시 노출된다. `.env` 의 토큰은 반드시 본인 계정의 user 토큰이어야 한다.

## 실행 전 확인 (필수)

상태·프레즌스는 팀 전체에 보이는 변경이다. 실행 전 반드시 아래를 사용자에게 보여주고 확인받는다:

- 상태 설정: 새 이모지 + 텍스트 (+ 만료 시각이 있으면 그것도)
- 상태 해제: "상태를 지울까요?"
- 프레즌스: `auto`(자동/활성) 인지 `away`(자리비움) 인지

## 실행

```bash
# 상태 설정 — 이모지는 :train: 처럼 콜론 포함 shortcode, 만료는 생략 가능(Unix 초, 생략/0 이면 안 지워짐)
"${CLAUDE_SKILL_DIR}/slack-status.sh" set-status "회의 중" ":calendar:"
"${CLAUDE_SKILL_DIR}/slack-status.sh" set-status "점심" ":hamburger:" 1893456000

# 상태 해제 (텍스트·이모지 비우고 만료 0)
"${CLAUDE_SKILL_DIR}/slack-status.sh" clear-status

# 프레즌스 — auto(자동/활성) 또는 away(자리비움) 만 허용
"${CLAUDE_SKILL_DIR}/slack-status.sh" presence away
"${CLAUDE_SKILL_DIR}/slack-status.sh" presence auto
```

`status_expiration` 은 상태가 사라질 시점의 Unix 초 타임스탬프다. 사용자가 "1시간 뒤 만료" 처럼 상대 시각을 주면 `date -v+1H +%s`(macOS) 등으로 절대 초로 변환해 전달한다.

## 응답 해석

응답 JSON 의 `ok` 필드를 확인한다. `false` 면 `error` 값을 그대로 사용자에게 보고한다 (자주 보는 값: `missing_scope` — 아래 스코프 미설정, `not_authed`/`invalid_auth` — 토큰 문제, `profile_status_set_failed` — 상태 형식 오류, `invalid_presence` — presence 인자 오류).

## 셋업

`slack-edit-message` 등 다른 Slack user-토큰 스킬과 **같은 Slack App / 같은 토큰**을 공유한다. 토큰은 한 번만 붙여넣으면 되도록 `~/.config/slack-user-token/.env` 를 가장 먼저 찾는다.

1. `.env.example` 을 `.env` 로 복사 (또는 공유 파일 `~/.config/slack-user-token/.env` 사용)
2. [api.slack.com/apps](https://api.slack.com/apps) → 기존 앱 선택 (없으면 Create New App → From scratch)
3. OAuth & Permissions → **User Token Scopes** 에 추가:
   - `users.profile:write` — 상태메시지 설정 (`set-status`/`clear-status`)
   - `users:write` — 프레즌스 설정 (`presence`)
4. Install(또는 Reinstall) to Workspace → **User OAuth Token** (`xoxp-` 로 시작, `xoxb-` 아님) 복사해 `.env` 의 `SLACK_USER_TOKEN` 에 붙여넣기
5. `chmod +x slack-status.sh`

`.env` 는 gitignore 된다 — 토큰은 로컬에만 두고 레포(PUBLIC)에 커밋하지 않는다.

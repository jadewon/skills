---
name: slack-edit-message
description: 내가 Slack 에 보낸 메시지를 수정(chat.update)하거나 삭제(chat.delete)한다. claude_ai Slack MCP 도구셋엔 수정/삭제가 없어 xoxp user 토큰으로 Slack Web API 를 직접 호출한다.
argument-hint: "<메시지 링크 또는 설명> 삭제해줘 | <메시지 링크 또는 설명> ...로 수정해줘"
allowed-tools: Bash, mcp__claude_ai_Slack__slack_search_public, mcp__claude_ai_Slack__slack_search_public_and_private, mcp__claude_ai_Slack__slack_read_channel, mcp__claude_ai_Slack__slack_read_thread
---

# Slack Message Edit/Delete

Slack 에 이미 보낸 내 메시지를 수정하거나 삭제한다. `mcp__claude_ai_Slack__*` 도구셋에는 `chat.update`/`chat.delete` 가 없어서, xoxp(user) 토큰으로 Slack Web API 를 직접 호출하는 이 스킬이 필요하다.

**주의**: Slack 은 본인이 보낸 메시지만 수정/삭제할 수 있게 한다 (관리자 특수 권한 예외). `.env` 에 넣는 토큰은 반드시 메시지를 보낸 본인 계정의 user 토큰이어야 한다.

## 1. 대상 메시지 특정

- 사용자가 Slack 퍼머링크를 주면 직접 파싱한다: `https://<workspace>.slack.com/archives/<CHANNEL_ID>/p<TS_DIGITS>`
  → `channel_id` = `<CHANNEL_ID>`, `ts` = `<TS_DIGITS>` 의 앞 10자리 + `.` + 나머지 (예: `p1234567890123456` → `1234567890.123456`)
- 링크가 없으면 `mcp__claude_ai_Slack__slack_search_public`(_and_private) / `slack_read_channel` / `slack_read_thread` 로 채널·시점을 좁혀 `channel_id` 와 `ts` 를 찾는다.
- 후보가 여러 개면 사용자에게 메시지 내용·시각을 보여주고 어떤 것인지 확인받는다.

## 2. 실행 전 확인 (필수)

삭제는 되돌릴 수 없고, 수정은 `(edited)` 표시가 영구히 남는다. 실행 전 반드시 아래를 사용자에게 보여주고 확인받는다:

- 채널, 시각, 현재 메시지 내용
- 삭제면 "삭제할까요?", 수정이면 새 텍스트 전문

## 3. 실행

```bash
"${CLAUDE_SKILL_DIR}/slack-edit-message.sh" update <channel_id> <ts> "<새 텍스트>"
"${CLAUDE_SKILL_DIR}/slack-edit-message.sh" delete <channel_id> <ts>
```

응답 JSON 의 `ok` 필드를 확인한다. `false` 면 `error` 값을 그대로 사용자에게 보고한다 (자주 보는 값: `cant_update_message`/`cant_delete_message` — 본인 메시지가 아님, `message_not_found`, `channel_not_found`, `not_authed`, `missing_scope`).

텍스트만 교체하며, 원본에 블록(첨부/버튼 등)이 있었다면 `update` 시 사라진다 — 순수 텍스트 메시지에만 쓴다.

## 셋업

1. `.env.example` 을 `.env` 로 복사
2. [api.slack.com/apps](https://api.slack.com/apps) → Create New App → From scratch
3. OAuth & Permissions → **User Token Scopes** 에 `chat:write` 추가 (초대 안 된 public 채널까지 다루려면 `chat:write.public` 도)
4. Install to Workspace → **User OAuth Token** (`xoxp-` 로 시작, `xoxb-` 아님) 복사해 `.env` 의 `SLACK_USER_TOKEN` 에 붙여넣기
5. `chmod +x slack-edit-message.sh`
6. 토큰 확인: `"${CLAUDE_SKILL_DIR}/slack-edit-message.sh" whoami` → `ok:true` + 본인 user id 가 나오면 정상

`.env` 는 gitignore 된다 — 토큰은 로컬에만 두고 레포(PUBLIC)에 커밋하지 않는다.

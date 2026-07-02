---
name: slack-pins
description: Slack 채널의 메시지를 핀 고정(pins.add)·해제(pins.remove)하거나 핀 목록(pins.list)을 조회한다. claude_ai Slack MCP 도구셋엔 핀 기능이 없어 xoxp user 토큰으로 Slack Web API 를 직접 호출한다.
argument-hint: "<메시지 링크 또는 설명> 핀 고정 | <메시지> 핀 해제 | <채널> 핀 목록"
allowed-tools: Bash, mcp__claude_ai_Slack__slack_search_public, mcp__claude_ai_Slack__slack_search_public_and_private, mcp__claude_ai_Slack__slack_read_channel, mcp__claude_ai_Slack__slack_read_thread
---

# Slack Pins

Slack 채널에서 메시지를 핀 고정하거나 해제하고, 핀 목록을 조회한다. `mcp__claude_ai_Slack__*` 도구셋에는 `pins.*` 가 없어서, xoxp(user) 토큰으로 Slack Web API 를 직접 호출하는 이 스킬이 필요하다.

핀 목록은 채널 전체에 보이는 공용 항목이라, 고정/해제는 채널 구성원 모두에게 즉시 보인다.

## 1. 대상 특정

- **핀 고정/해제**는 채널 id 와 메시지 ts 가 필요하다.
  - 사용자가 Slack 퍼머링크를 주면 직접 파싱한다: `https://<workspace>.slack.com/archives/<CHANNEL_ID>/p<TS_DIGITS>`
    → `channel_id` = `<CHANNEL_ID>`, `ts` = `<TS_DIGITS>` 의 앞 10자리 + `.` + 나머지 (예: `p1234567890123456` → `1234567890.123456`)
  - 링크가 없으면 `mcp__claude_ai_Slack__slack_search_public`(_and_private) / `slack_read_channel` / `slack_read_thread` 로 채널·시점을 좁혀 `channel_id` 와 `ts` 를 찾는다.
  - 후보가 여러 개면 사용자에게 메시지 내용·시각을 보여주고 어떤 것인지 확인받는다.
- **핀 목록**은 채널 id 만 필요하다.

## 2. 실행 전 확인 (add / remove 만)

핀 고정·해제는 채널 전체의 핀 목록을 바꾸며 구성원 모두에게 보인다. `add`/`remove` 실행 전 반드시 아래를 사용자에게 보여주고 확인받는다:

- 채널, 대상 메시지 내용·시각
- 고정할지 / 해제할지

`list` 는 읽기 전용이라 확인 없이 바로 실행한다.

## 3. 실행

```bash
"${CLAUDE_SKILL_DIR}/slack-pins.sh" add <channel_id> <ts>
"${CLAUDE_SKILL_DIR}/slack-pins.sh" remove <channel_id> <ts>
"${CLAUDE_SKILL_DIR}/slack-pins.sh" list <channel_id>
```

응답 JSON 의 `ok` 필드를 확인한다. `false` 면 `error` 값을 그대로 사용자에게 보고한다 (자주 보는 값: `already_pinned` / `not_pinned`, `message_not_found`, `channel_not_found`, `not_authed`, `missing_scope`, `permission_denied`).

`list` 성공 시 `items` 배열에 핀 항목이 들어온다 (메시지는 `type:"message"` + `message.text`/`message.ts`).

## 셋업

1. `.env.example` 을 `.env` 로 복사
2. `slack-edit-message` 와 **같은 Slack App** 을 쓴다. [api.slack.com/apps](https://api.slack.com/apps) → 해당 App → OAuth & Permissions → **User Token Scopes** 에 `pins:write` (고정/해제) 와 `pins:read` (목록) 추가
3. 스코프를 추가했으면 Reinstall to Workspace → **User OAuth Token** (`xoxp-` 로 시작, `xoxb-` 아님) 복사
4. 토큰은 다른 Slack 스킬과 공유하는 `~/.config/slack-user-token/.env` 의 `SLACK_USER_TOKEN` 에 한 번만 넣어두면 된다 (없으면 이 디렉토리의 `.env` 에 넣어도 됨)
5. `chmod +x slack-pins.sh`

`.env` 는 gitignore 된다 — 토큰은 로컬에만 두고 레포(PUBLIC)에 커밋하지 않는다.

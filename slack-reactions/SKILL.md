---
name: slack-reactions
description: Slack 메시지의 반응(이모지)을 제거(reactions.remove)하거나 내가/특정 유저가 남긴 반응 목록을 조회(reactions.list)한다. claude_ai Slack MCP 도구셋엔 add_reaction/get_reactions 만 있고 제거/목록이 없어 xoxp user 토큰으로 Slack Web API 를 직접 호출한다.
argument-hint: "<메시지 링크 또는 설명> 에서 :emoji: 반응 빼줘 | 내가 남긴 반응 목록 보여줘"
allowed-tools: Bash, mcp__claude_ai_Slack__slack_search_public, mcp__claude_ai_Slack__slack_search_public_and_private, mcp__claude_ai_Slack__slack_read_channel, mcp__claude_ai_Slack__slack_read_thread, mcp__claude_ai_Slack__slack_get_reactions
---

# Slack Reactions Remove/List

Slack 메시지에 달린 반응(이모지)을 제거하거나, 특정 유저(기본: 토큰 소유자)가 남긴 반응 목록을 조회한다. `mcp__claude_ai_Slack__*` 도구셋에는 `slack_add_reaction`/`slack_get_reactions` 만 있고 `reactions.remove`/`reactions.list` 가 없어서, xoxp(user) 토큰으로 Slack Web API 를 직접 호출하는 이 스킬이 필요하다.

**주의**: user 토큰으로 제거할 수 있는 건 원칙적으로 본인이 남긴 반응이다. `.env` 에 넣는 토큰은 반응을 남긴 본인 계정의 user 토큰이어야 한다.

## remove — 반응 제거

### 1. 대상 메시지 특정

- 사용자가 Slack 퍼머링크를 주면 직접 파싱한다: `https://<workspace>.slack.com/archives/<CHANNEL_ID>/p<TS_DIGITS>`
  → `channel_id` = `<CHANNEL_ID>`, `ts` = `<TS_DIGITS>` 의 앞 10자리 + `.` + 나머지 (예: `p1234567890123456` → `1234567890.123456`)
- 링크가 없으면 `mcp__claude_ai_Slack__slack_search_public`(_and_private) / `slack_read_channel` / `slack_read_thread` 로 채널·시점을 좁혀 `channel_id` 와 `ts` 를 찾는다.
- 지울 이모지 이름은 콜론 없이 넘긴다 (예: `thumbsup`, `+1`). 현재 달린 반응이 헷갈리면 `mcp__claude_ai_Slack__slack_get_reactions` 로 확인한다.

### 2. 실행 전 확인 (필수)

반응 제거는 다른 사람 화면에서도 그 이모지가 사라지는, 눈에 보이는 변경이다. 실행 전 반드시 아래를 사용자에게 보여주고 확인받는다:

- 채널, 시각, 대상 메시지 내용
- 제거할 이모지 이름 (예: `:thumbsup:`)

### 3. 실행

```bash
"${CLAUDE_SKILL_DIR}/slack-reactions.sh" remove <channel_id> <ts> <emoji_name>
```

## list — 반응 목록 조회 (읽기 전용)

내가(토큰 소유자) 또는 특정 유저가 남긴 반응들을 조회한다. 읽기 전용이라 확인 절차 없이 바로 실행해도 된다.

```bash
"${CLAUDE_SKILL_DIR}/slack-reactions.sh" list            # 토큰 소유자 본인
"${CLAUDE_SKILL_DIR}/slack-reactions.sh" list <user_id>  # 특정 유저 (예: U012ABCDEF)
```

`user_id` 를 생략하면 Slack 이 알아서 인증된 토큰 소유자 기준으로 반환한다.

## 응답 해석

응답 JSON 의 `ok` 필드를 확인한다. `false` 면 `error` 값을 그대로 사용자에게 보고한다 (자주 보는 값: `no_reaction` — 그 이모지가 안 달려 있음, `message_not_found`, `channel_not_found`, `not_authed`, `missing_scope`, `invalid_name` — 이모지 이름 오타).

## 셋업

1. `.env.example` 을 `.env` 로 복사
2. [api.slack.com/apps](https://api.slack.com/apps) → slack-edit-message 와 **동일한 App** 을 쓴다 (없으면 Create New App → From scratch)
3. OAuth & Permissions → **User Token Scopes** 에 `reactions:write`(제거용), `reactions:read`(목록용) 추가
4. Install to Workspace → **User OAuth Token** (`xoxp-` 로 시작, `xoxb-` 아님) 복사해 `.env` 의 `SLACK_USER_TOKEN` 에 붙여넣기
   - 여러 Slack 스킬이 토큰을 공유한다 — 한 번만 붙여넣으려면 `~/.config/slack-user-token/.env` 에 두면 이 스킬이 먼저 그 경로를 읽는다
5. `chmod +x slack-reactions.sh`

`.env` 는 gitignore 된다 — 토큰은 로컬에만 두고 레포(PUBLIC)에 커밋하지 않는다.

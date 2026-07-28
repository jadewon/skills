---
name: slack-scheduled-message
description: Schedule a future-dated Slack message (to a configured channel; default self-DM) that includes a `cd <pwd> && claude --resume <session>` command, so you can pick up the current Claude Code conversation at the scheduled moment. Timezone Asia/Seoul.
disable-model-invocation: false
argument-hint: "<when> <message> [as <custom-name>]  (e.g. 5/11 09:32 컨텍스트 정리 — as plugin-marketplace)"
allowed-tools: Bash, AskUserQuestion, mcp__slack__slack_api, mcp__slack__slack_list_users, mcp__slack__slack_list_channels
---

# Slack Scheduled Message (with Claude Resume command)

Schedule a Slack message to a configured destination (default: self-DM, but a private channel is recommended for reliable push notifications). The message embeds the command to resume the **current** Claude Code session, so the user lands back into this conversation when the message arrives.

> ⚠️ **Self-DM caveat:** Slack suppresses push/sound/badge notifications on self-DMs regardless of sender (the Claude Slack app does NOT bypass this). Only the unread badge inside the DM channel appears. For reliable push at the scheduled time, configure a single-member private channel (e.g. `#jade-notes`) at first-time setup.

Timezone: **Asia/Seoul (KST)** — all date/time inputs are interpreted in KST.

## Input

`$ARGUMENTS` — natural language. Parse out:

| Part | Required | Examples |
|------|----------|----------|
| **date** | yes | `5/11`, `5월 11일`, `내일`, `다음주 월요일`, `2026-05-11` |
| **time** | yes | `09:32`, `오전 9시 32분`, `9:32am`, `21:00` |
| **message** | yes | free-form note |
| **custom-name** | no | resume label (e.g. `as plugin-marketplace`, `이름: skill-design`) |

If only time is given, use today (or tomorrow if past). If a relative spec like `3분뒤` is given, compute the absolute KST date+time first.

## Steps

### 1. Run the helper

```bash
"${CLAUDE_SKILL_DIR}/slack-scheduled-message.sh" prepare <YYYY-MM-DD> <HH:MM> [custom-name]
```

Outputs `KEY=VALUE` lines: `PWD`, `SESSION_ID`, `SESSION_NAME`, `POST_AT`, `POST_AT_HUMAN`, `RESUME_TARGET`, `RESUME_SOURCE`, `CACHED_CHANNEL_ID`.

The helper enforces the 2-min minimum / 120-day maximum and resolves the resume target via `user_custom_name ?? session_name ?? $CLAUDE_CODE_SESSION_ID`. If it exits non-zero, surface its stderr message and stop.

### 2. Resolve `channel_id`

If `CACHED_CHANNEL_ID` is non-empty → use it.

Otherwise (first-time setup) — use `AskUserQuestion`:

- **header:** `Target`
- **question:** `Slack 메시지를 어디로 보낼까? (본인 DM 은 알림 없음 — 푸시 받으려면 private 채널 추천)`
- **options:**
  1. `특정 채널/그룹 (Recommended)` — `private 채널 또는 그룹 DM. 다음에 채널 이름 입력받아 resolve.`
  2. `내 DM (알림 약함)` — `본인에게 DM. unread 배지만 뜨고 push/sound 알림 없음.`

Then resolve:
- **내 DM** → call `mcp__slack__slack_list_users` with the user's name as `query`; pick the matching `id`.
- **특정 채널** → follow up with another `AskUserQuestion` (header `Channel name`, options `직접 입력` × 2; user types the name in Other). Then `mcp__slack__slack_list_channels` with that name as `query` to resolve. If multiple matches, list and ask.

Save the chosen id:

```bash
"${CLAUDE_SKILL_DIR}/slack-scheduled-message.sh" save-channel <slack-id>
```

### 3. Compose body

````
<user's free-form message>

```bash
cd "<PWD>" && claude --resume "<RESUME_TARGET>"
```
````

The triple-backtick block makes the command tap-to-copy in Slack.

### 4. Schedule

`mcp__slack__slack_api` with `method` = `chat.scheduleMessage` and `params`:
- `channel` = step 2 result
- `text` = step 3 body
- `post_at` = `POST_AT` from step 1

Keep `scheduled_message_id` from the response — it is what step 6 cancels with.

### 5. Confirm

One short summary, no raw API JSON:

```
✅ Scheduled  <POST_AT_HUMAN>
   → <DM to self>  |  <#channel-name>

──── preview ────
<rendered body>
─────────────────
```

### 6. 예약 조회/취소 (선택)

`mcp__slack__slack_api` 로 처리한다.

- 조회 — `method` = `chat.scheduledMessages.list`, `params.channel` = 채널 id (생략하면 전체)
- 취소 — `method` = `chat.deleteScheduledMessage`, `params` = `{channel, scheduled_message_id}`

조회 응답의 `scheduled_messages[].id` 가 취소에 쓰는 `scheduled_message_id` 다.

## Notes

- Resume target precedence: `user_custom_name ?? session_name ?? $CLAUDE_CODE_SESSION_ID`.
- Session name is set via Claude Code's `/name` (read from `~/.claude/sessions/<pid>.json`).
- To switch destinations, `rm ~/.config/slack-scheduled-message/channel_id`.

## 셋업

1. `mcp__slack__*` MCP 서버가 등록되어 있어야 한다 — [jadewon/mcps `slack-mcp`](https://github.com/jadewon/mcps/tree/main/slack-mcp). 토큰(`SLACK_USER_TOKEN`, `chat:write` 스코프)은 그 서버가 관리하므로 이 스킬엔 별도 `.env` 가 필요 없다.
2. `chmod +x slack-scheduled-message.sh`

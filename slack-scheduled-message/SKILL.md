---
name: slack-scheduled-message
description: Schedule a future-dated Slack message (sent as the bot, to a configured channel) that includes a `cd <pwd> && claude --resume <session>` command, so you can pick up the current Claude Code conversation at the scheduled moment. Timezone Asia/Seoul.
disable-model-invocation: false
argument-hint: "<when> <message> [as <custom-name>]  (e.g. 5/11 09:32 컨텍스트 정리 — as plugin-marketplace)"
allowed-tools: Bash, AskUserQuestion, mcp__slack__slack_api, mcp__slack__slack_list_channels
---

# Slack Scheduled Message (with Claude Resume command)

Schedule a Slack message to a configured channel. The message embeds the command to resume the **current** Claude Code session, so the user lands back into this conversation when the message arrives.

> **The message is sent as the bot** — `as: "bot"` on the schedule, list and cancel calls. (The
> one-off channel invite in first-time setup is the exception: you issue that as yourself.)
> Slack never notifies you about a message you sent yourself, so a reminder posted with the
> user token arrives silently — which is exactly the failure this skill exists to avoid. Two
> consequences: the destination must be a **channel the bot is a member of** (a self-DM is
> unreachable for it), and the scheduled message is only visible to and cancellable by the bot
> identity, so listing and cancelling need `as: "bot"` too.

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

Otherwise (first-time setup) — ask which channel with `AskUserQuestion` (header `Channel name`,
options `직접 입력` × 2; the user types the name in Other), then resolve it with
`mcp__slack__slack_list_channels` using that name as `query`. If several match, list them and ask.

A user's own DM is not an option: the bot cannot post there, and a self-sent message would not
notify anyway. A single-member private channel (e.g. `#jade-notes`) is the equivalent.

The bot must be in that channel. If a later step fails with `not_in_channel`, resolve the bot's
own id — `mcp__slack__slack_api` `auth.test` with `as` = `bot`, take `user_id` from the response —
then invite it: `conversations.invite` with `as` omitted (the *user* issues the invite),
`params` = `{channel, users: <that id>}`. Retry afterwards.

Save the chosen id:

```bash
"${CLAUDE_SKILL_DIR}/slack-scheduled-message.sh" save-channel <slack-id>
```

### 3. Compose body

````
:alarm_clock: <user's free-form message>

```
cd "<PWD>" && claude --resume "<RESUME_TARGET>"
```
````

**`:alarm_clock:` is mandatory and always first.** It is the only marker that tells a scheduled
message apart from the other bot traffic in the channel — without it the message reads as one
more notification and gets scrolled past. Never drop it, never swap it for a topic emoji; a
topic emoji goes *after* it (`:alarm_clock: :rocket: 배포 …`).

**No language tag on the fence.** Slack does not highlight fenced code, so a ` ```bash ` tag
renders as a literal `bash` line inside the snippet and gets copied along with the command.
Open the fence with bare ` ``` ` on its own line.

The triple-backtick block makes the command tap-to-copy in Slack.

### 4. Schedule

`mcp__slack__slack_api` with `method` = `chat.scheduleMessage`, `as` = `bot`, and `params`:
- `channel` = step 2 result
- `text` = step 3 body
- `post_at` = `POST_AT` from step 1

Keep `scheduled_message_id` from the response — it is what step 6 cancels with.

Never drop `as: "bot"` here. Without it the message is authored by the user, and Slack delivers
it with no push, no sound and no badge — it looks scheduled but silently never arrives.

### 5. Confirm

One short summary, no raw API JSON:

```
✅ Scheduled  <POST_AT_HUMAN>
   → <#channel-name>  (as the bot)

──── preview ────
<rendered body>
─────────────────
```

### 6. 예약 조회/취소 (선택)

`mcp__slack__slack_api` 로 처리하며, **`as` = `bot` 이 반드시 필요하다** — 예약을 만든 주체가 봇이라
user 토큰으로 조회하면 그 예약이 목록에 아예 안 나오고, 취소도 안 된다.

- 조회 — `method` = `chat.scheduledMessages.list`, `as` = `bot`, `params.channel` = 채널 id (생략하면 전체)
- 취소 — `method` = `chat.deleteScheduledMessage`, `as` = `bot`, `params` = `{channel, scheduled_message_id}`

조회 응답의 `scheduled_messages[].id` 가 취소에 쓰는 `scheduled_message_id` 다.

봇 도입 이전에 user 토큰으로 걸어둔 예약이 남아 있다면 그것들은 반대로 `as` 없이 조회해야 보인다.

## Notes

- Resume target precedence: `user_custom_name ?? session_name ?? $CLAUDE_CODE_SESSION_ID`.
- Session name is set via Claude Code's `/name` (read from `~/.claude/sessions/<pid>.json`).
- To switch destinations, `rm ~/.config/slack-scheduled-message/channel_id`.

## 셋업

1. `mcp__slack__*` MCP 서버가 등록되어 있어야 한다 — [jadewon/mcps `slack-mcp`](https://github.com/jadewon/mcps/tree/main/slack-mcp). 토큰은 그 서버가 관리하므로 이 스킬엔 별도 `.env` 가 필요 없다. `~/.config/slack-user-token/.env` 에 두 개가 필요하다: `SLACK_USER_TOKEN` (xoxp) 과 `SLACK_BOT_TOKEN` (xoxb, `chat:write` — `as: "bot"` 이 이걸 쓴다).
2. 발송 대상 채널에 봇이 멤버로 들어가 있어야 한다.
3. `chmod +x slack-scheduled-message.sh`

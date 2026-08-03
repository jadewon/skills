# slack-scheduled-message

Schedule a future-dated Slack message to a channel that includes a `cd <pwd> && claude --resume <session>` command — so when the message lands, you can tap the snippet and drop straight back into the **current** Claude Code conversation.

> ⚠️ **Read first:** the message is sent **as the bot**, not as you. Slack never notifies you about your own message, so a self-sent reminder arrives silently. That makes the bot identity load-bearing — see [Caveats](#caveats).

> [한국어](./README.ko.md)

## Why

You're mid-conversation with Claude Code, but the next step is on a future date (a meeting, a deploy window, a scheduled review). Instead of leaving a mental TODO, schedule a Slack message to your future self carrying the exact resume command for *this* session.

## Usage

```
/slack-scheduled-message 5/11 09:32 회의 끝나고 컨텍스트 정리 이어가기
/slack-scheduled-message 내일 21:00 다음 단계 PR 분기 as plugin-marketplace
/slack-scheduled-message 2026-05-15 14:00 데모 직전 마지막 점검
```

Also natural language:

```
5월 11일 월요일 9시 32분에 슬랙으로 알려줘 — 컨텍스트 이어가는 거 잊지 말라고 (이름: skill-design)
```

## What gets sent

````
:alarm_clock: <your message>

```
cd "<current path>" && claude --resume "<custom name ?? current session id>"
```
````

Every scheduled message opens with `:alarm_clock:` so it is distinguishable at a glance from the
other bot traffic in the channel. The code fence carries no language tag — Slack would render
`bash` as a literal first line of the snippet and copy it along with the command.

**Resume target resolution:** `user_custom_name ?? session_name ?? $CLAUDE_CODE_SESSION_ID`
1. Explicit `as <name>` / `이름: <name>` from your input wins.
2. Else: the current session's name set via Claude Code's `/name` (read from `~/.claude/sessions/<pid>.json`).
3. Else: the raw UUID.

## Behavior

- **Timezone:** Asia/Seoul (KST)
- **Sender:** the bot (`as: "bot"`), never you — see [Caveats](#caveats)
- **Destination:** a channel, asked once on first use and cached at `~/.config/slack-scheduled-message/channel_id`. To switch, `rm` the cache file.
- **Resume target:** `user_custom_name ?? session_name ?? $CLAUDE_CODE_SESSION_ID` (earlier wins)
- **Bounds:** Slack scheduling requires ≥2 minutes future, ≤120 days out

## Caveats

**Slack never notifies you about a message you sent yourself** — no push, no sound, no badge, in any channel, self-DM or not. A reminder scheduled with the user token therefore arrives silently: it is in the channel, and you never find out. This is not a self-DM quirk and no client setting overrides it.

So every send this skill makes is signed with the bot token (`as: "bot"` on `mcp__slack__slack_api`) — scheduling, listing and cancelling alike. The author is somebody else, so the notification fires normally. Two things follow:

- The destination must be a **channel the bot belongs to**. Your own DM cannot work — the bot has no access to it, and a message you sent yourself would not notify you anyway. Use a single-member private channel instead (e.g. `#jade-notes`) and invite the bot.
- The scheduled message **belongs to the bot**: it does not appear in your own `chat.scheduledMessages.list`, and only the bot token can cancel it.

## Cancel / list

Both go through `mcp__slack__slack_api` **with `as: "bot"`** — without it the scheduled message is invisible and uncancellable:

- list — `method` `chat.scheduledMessages.list`, `as` `bot`, `params.channel` (omit for every channel)
- cancel — `method` `chat.deleteScheduledMessage`, `as` `bot`, `params` `{channel, scheduled_message_id}`

Messages still can't be *edited* via API — cancel and reschedule instead.

## Setup

`~/.config/slack-user-token/.env` needs both `SLACK_USER_TOKEN` (xoxp) and `SLACK_BOT_TOKEN` (xoxb with `chat:write`); the [slack-mcp](https://github.com/jadewon/mcps/tree/main/slack-mcp) server reads them. Invite that bot to the destination channel.

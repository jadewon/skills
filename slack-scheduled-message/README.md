# slack-scheduled-message

Schedule a future-dated Slack message (default: self-DM, recommended: a private channel) that includes a `cd <pwd> && claude --resume <session>` command — so when the message lands, you can tap the snippet and drop straight back into the **current** Claude Code conversation.

> ⚠️ **Read first:** Slack suppresses notifications on self-DMs. On first use, the skill asks where to send via `AskUserQuestion`. Pick a private channel if you want push to actually fire. See [Caveats](#caveats).

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

```
<your message>

```bash
cd "<current path>" && claude --resume "<custom name ?? current session id>"
```
```

**Resume target resolution:** `user_custom_name ?? session_name ?? $CLAUDE_CODE_SESSION_ID`
1. Explicit `as <name>` / `이름: <name>` from your input wins.
2. Else: the current session's name set via Claude Code's `/name` (read from `~/.claude/sessions/<pid>.json`).
3. Else: the raw UUID.

## Behavior

- **Timezone:** Asia/Seoul (KST)
- **Destination:** asked once on first use via `AskUserQuestion` — choose `내 DM` (default, no push) or `특정 채널/그룹` (recommended for notifications). Cached at `~/.config/slack-scheduled-message/channel_id`. To switch, `rm` the cache file.
- **Resume target:** `user_custom_name ?? session_name ?? $CLAUDE_CODE_SESSION_ID` (earlier wins)
- **Bounds:** Slack scheduling requires ≥2 minutes future, ≤120 days out

## Caveats

Slack suppresses push, sound, and badge notifications on self-DMs regardless of sender — sending via the Claude Slack app does not bypass this. Only the unread badge inside the DM channel itself appears. If you need a reliable push at the scheduled time, schedule into a single-member private channel instead (e.g. `#jade-notes`), or include a self-mention `<@U…>` in the message (re-enables notifications in some workspaces, but is workspace-dependent).

## Cancel / list

```bash
slack-scheduled-message.sh list-scheduled <channel_id>
slack-scheduled-message.sh cancel-scheduled <channel_id> <scheduled_message_id>
```

Needs `SLACK_USER_TOKEN` (see `.env.example`) — the schedule step itself uses the MCP tool and needs no token, but list/cancel call `chat.scheduledMessages.list` / `chat.deleteScheduledMessage` directly since those aren't in the MCP tool set. Messages still can't be *edited* via API — cancel and reschedule instead.

---
name: slack-bookmarks
description: Slack 채널 상단의 링크 북마크 바를 관리한다 (bookmarks.add/edit/remove/list). claude_ai Slack MCP 도구셋엔 북마크 기능이 없어 xoxp user 토큰으로 Slack Web API 를 직접 호출한다.
argument-hint: "<채널>에 <제목> 북마크 추가 | <채널> 북마크 목록 | <채널>의 <북마크> 수정/삭제"
allowed-tools: Bash, mcp__claude_ai_Slack__slack_search_channels, mcp__claude_ai_Slack__slack_read_channel, mcp__claude_ai_Slack__slack_search_public, mcp__claude_ai_Slack__slack_search_public_and_private
---

# Slack Channel Bookmarks

Slack 채널 상단에 표시되는 **링크 북마크 바**를 관리한다 (채널 이름 밑 줄에 붙는 즐겨찾기 링크들 — canvas 와는 별개). `mcp__claude_ai_Slack__*` 도구셋에는 `bookmarks.*` 가 없어서, xoxp(user) 토큰으로 Slack Web API 를 직접 호출하는 이 스킬이 필요하다.

## 1. 대상 채널 특정 (channel_id)

거의 모든 서브커맨드가 `channel_id` 를 요구한다 (public 채널은 필수, private/DM 도 채널 지정용으로 사실상 필요).

- 사용자가 채널 퍼머링크를 주면 파싱한다: `https://<workspace>.slack.com/archives/<CHANNEL_ID>/...` → `channel_id` = `<CHANNEL_ID>`
- 채널 이름만 알면 `mcp__claude_ai_Slack__slack_search_channels` 로 `channel_id` 를 찾는다.
- 어떤 북마크를 수정/삭제할지 알려면 먼저 `list` 로 각 북마크의 `id` 를 확인한다.

## 2. 실행 전 확인 (add / edit / remove 필수)

북마크 바는 채널의 **모든 멤버에게 보이는** 공용 영역이다. `add`/`edit`/`remove` 는 전원에게 즉시 노출되므로, 실행 전 반드시 아래를 사용자에게 보여주고 확인받는다:

- 대상 채널
- 무엇을 할지: 추가면 `제목 + URL`, 수정이면 `대상 북마크 id + 새 제목/URL`, 삭제면 `대상 북마크 id + 현재 제목`

`list` 는 읽기 전용이라 확인 없이 바로 실행한다.

## 3. 실행

```bash
"${CLAUDE_SKILL_DIR}/slack-bookmarks.sh" list   <channel_id>
"${CLAUDE_SKILL_DIR}/slack-bookmarks.sh" add    <channel_id> "<제목>" "<URL>"
"${CLAUDE_SKILL_DIR}/slack-bookmarks.sh" edit   <channel_id> <bookmark_id> "<새 제목>" "<새 URL>"
"${CLAUDE_SKILL_DIR}/slack-bookmarks.sh" remove <channel_id> <bookmark_id>
```

`bookmark_id` 는 `list` 응답의 `bookmarks[].id` 값이다 (예: `Bk0123ABCD`).

응답 JSON 의 `ok` 필드를 확인한다. `false` 면 `error` 값을 그대로 사용자에게 보고한다 (자주 보는 값: `not_authed`, `missing_scope` — 스코프 미부여, `channel_not_found`, `bookmark_not_found`, `restricted_action` — 워크스페이스 정책상 북마크 편집 제한, `no_permission`).

## 셋업

1. `.env.example` 을 `.env` 로 복사
2. slack-edit-message 와 **같은 Slack App** 을 쓴다 ([api.slack.com/apps](https://api.slack.com/apps) → 기존 앱, 없으면 Create New App → From scratch)
3. OAuth & Permissions → **User Token Scopes** 에 `bookmarks:read` + `bookmarks:write` 추가 (출처: <https://docs.slack.dev/reference/methods/bookmarks.add>, `bookmarks.list` 는 `bookmarks:read`)
4. Reinstall to Workspace → **User OAuth Token** (`xoxp-` 로 시작, `xoxb-` 아님) 복사
5. 토큰은 다른 slack-* 스킬과 공유한다 — `~/.config/slack-user-token/.env` 의 `SLACK_USER_TOKEN` 에 한 번만 붙여넣으면 이 스킬도 그 파일을 가장 먼저 찾아 쓴다. (스킬 로컬 `.env` 에 따로 둬도 됨)
6. `chmod +x slack-bookmarks.sh`

`.env` 는 gitignore 된다 — 토큰은 로컬에만 두고 레포(PUBLIC)에 커밋하지 않는다.

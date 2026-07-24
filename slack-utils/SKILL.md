---
name: slack-utils
description: claude_ai Slack MCP 도구셋에 없는 단일 엔드포인트 유틸들 — 메시지 퍼머링크 생성(chat.getPermalink), 캔버스 삭제(canvases.delete), 메시지 원본 JSON 조회(conversations.history, attachments/blocks 포함)를 xoxp user 토큰으로 Slack Web API 직접 호출한다.
argument-hint: "<메시지> 링크 만들어줘 | 캔버스 <canvas_id> 삭제해줘 | <메시지> 원본(attachments/blocks) 읽어줘"
allowed-tools: Bash, mcp__claude_ai_Slack__slack_search_public, mcp__claude_ai_Slack__slack_search_public_and_private, mcp__claude_ai_Slack__slack_read_channel, mcp__claude_ai_Slack__slack_read_thread
---

# Slack Utils

`mcp__claude_ai_Slack__*` 도구셋이 커버하지 못하는 단일 엔드포인트 유틸들을 xoxp(user) 토큰으로 직접 호출한다.

- `permalink` — 특정 메시지의 공유 가능한 퍼머링크 생성 (`chat.getPermalink`). MCP 도구셋엔 퍼머링크 생성이 없다.
- `delete-canvas` — 캔버스 삭제 (`canvases.delete`). MCP 도구셋은 캔버스 생성·읽기·수정은 되지만 삭제는 없다.
- `read` — 메시지 원본 JSON 조회 (`conversations.history`). MCP 도구셋(`slack_read_thread`/`slack_read_channel`)은 `text` 필드만 주고 `attachments`/`blocks`(rich text, 카드형 attachment 등)는 안 줘서, 서식을 그대로 참고해야 할 때 이걸 쓴다.

`permalink` 은 `channel_id`+`ts` → 퍼머링크의 방향이라, `slack-edit-message` 가 퍼머링크를 `channel_id`+`ts` 로 파싱하는 것의 정확히 역연산이다 — 그 스킬로 수정/삭제한 뒤 결과 메시지 링크를 다시 만들어 공유할 때 바로 이어 쓸 수 있다.

## permalink — 메시지 퍼머링크 생성

읽기 전용이라 확인 없이 실행해도 된다.

### 대상 메시지 특정

- `channel_id` 와 `ts` 를 이미 알면 그대로 쓴다.
- 모르면 `mcp__claude_ai_Slack__slack_search_public`(_and_private) / `slack_read_channel` / `slack_read_thread` 로 채널·시점을 좁혀 찾는다.

### 실행

```bash
"${CLAUDE_SKILL_DIR}/slack-utils.sh" permalink <channel_id> <ts>
```

성공하면 퍼머링크 문자열 한 줄만 stdout 으로 출력한다. 실패하면 응답 JSON 을 stderr 로 내보내고 exit 2 한다 — `error` 값을 그대로 사용자에게 보고한다 (자주 보는 값: `message_not_found`, `channel_not_found`, `not_authed`).

## delete-canvas — 캔버스 삭제

### 실행 전 확인 (필수)

캔버스 삭제는 되돌릴 수 없다. 실행 전 반드시 대상 캔버스(제목·내용·`canvas_id`)를 사용자에게 보여주고 "삭제할까요?" 확인받은 뒤 실행한다.

### 실행

```bash
"${CLAUDE_SKILL_DIR}/slack-utils.sh" delete-canvas <canvas_id>
```

응답 JSON 의 `ok` 필드를 확인한다. `false` 면 `error` 값을 그대로 보고한다 (자주 보는 값: `canvas_not_found`, `missing_scope`, `not_authed`).

## read — 메시지 원본 JSON 조회

읽기 전용이라 확인 없이 실행해도 된다.

### 실행

```bash
"${CLAUDE_SKILL_DIR}/slack-utils.sh" read <channel_id> <ts>
```

`conversations.history`(`latest=<ts>&inclusive=true&limit=1`)로 해당 메시지 하나를 통째로 가져와 `messages[0]` 객체를 그대로 출력한다 — `text`, `attachments`, `blocks`, `bot_id` 등 원본 필드 전부 포함. Public 채널은 기존 토큰 스코프로 바로 됨을 확인함; private 채널/그룹은 `groups:history` 스코프가 없으면 `missing_scope`로 실패할 수 있음(미검증) — 그 경우 delete-canvas 때처럼 User Token Scopes에 추가 후 Reinstall 필요.

## 셋업

1. `.env.example` 을 `.env` 로 복사
2. `slack-edit-message` 와 **같은 Slack App / 같은 user 토큰**을 쓴다. 공유 토큰 파일 `~/.config/slack-user-token/.env` 에 `SLACK_USER_TOKEN` 을 한 번만 넣어두면 이 스킬도 그걸 자동으로 찾는다 (별도 토큰 파일 불필요).
3. 스코프 추가: [api.slack.com/apps](https://api.slack.com/apps) → 기존 앱 → OAuth & Permissions → **User Token Scopes** 에 `canvases:write` 추가 (캔버스 삭제용) → Reinstall to Workspace. `chat.getPermalink` 은 별도 스코프가 필요 없다.
4. `chmod +x slack-utils.sh`

`.env` 는 gitignore 된다 — 토큰은 로컬에만 두고 레포(PUBLIC)에 커밋하지 않는다.

---
name: slack-files
description: 로컬 파일을 Slack 채널에 업로드하거나 업로드된 파일을 삭제한다. claude_ai Slack MCP 도구셋엔 업로드/삭제가 없어 xoxp user 토큰으로 Slack Web API 를 직접 호출한다.
argument-hint: "<파일 경로> 를 <채널> 에 올려줘 | <file_id> 삭제해줘"
allowed-tools: Bash, mcp__claude_ai_Slack__slack_search_channels
---

# Slack File Upload/Delete

로컬 파일을 Slack 채널에 올리거나(`upload`), 이미 올라간 파일을 삭제한다(`delete`). `mcp__claude_ai_Slack__*` 도구셋에는 파일 업로드/삭제가 없어서(읽기 `slack_read_file` 만 있음), xoxp(user) 토큰으로 Slack Web API 를 직접 호출하는 이 스킬이 필요하다.

업로드는 2025-11-12 에 sunset 된 `files.upload` 대신 현재의 external-upload 3단계 흐름을 쓴다: `files.getUploadURLExternal` 로 업로드 URL 을 받고 → 그 URL 에 파일 바이트를 raw binary 로 POST 하고 → `files.completeUploadExternal` 로 채널에 공유하며 마무리한다. (스크립트가 이 3단계를 한 번의 `upload` 호출로 처리한다.)

## 1. 채널 특정 (업로드)

- 사용자가 채널 ID(`C...`)를 직접 주면 그대로 쓴다.
- 채널 이름만 주면 `mcp__claude_ai_Slack__slack_search_channels` 로 `channel_id` 를 찾는다.
- 후보가 여럿이면 사용자에게 보여주고 확인받는다.

## 2. 실행 전 확인 (필수)

업로드는 실제 채널에 남들이 보는 파일을 올리고, 삭제는 되돌릴 수 없다. 실행 전 반드시 아래를 사용자에게 보여주고 확인받는다:

- 업로드면: 대상 채널, 올릴 파일 경로, (있으면) 제목·코멘트
- 삭제면: 대상 `file_id` 와 "삭제할까요?"

## 3. 실행

```bash
"${CLAUDE_SKILL_DIR}/slack-files.sh" upload <channel_id> <file_path> [title] [comment]
"${CLAUDE_SKILL_DIR}/slack-files.sh" delete <file_id>
```

- `title` 생략 시 파일 이름이 그대로 제목이 된다. `comment` 를 주면 파일과 함께 소개 메시지(initial_comment)로 붙는다.
- `upload` 성공 시 `files.completeUploadExternal` 응답 JSON 이 출력된다. `.files[].id` 가 나중에 `delete` 에 쓰는 `file_id` 다.

응답 JSON 의 `ok` 필드를 확인한다. `false` 면 `error` 값을 그대로 사용자에게 보고한다 (자주 보는 값: `not_authed`/`invalid_auth` — 토큰 문제, `missing_scope` — `files:write` 없음, `channel_not_found`, `file_not_found`, `cant_delete_file` — 본인 파일이 아님). 파일 바이트 업로드(2단계)가 실패하면 HTTP 오류로 non-zero 종료한다.

## 셋업

1. `.env.example` 을 `.env` 로 복사
2. slack-edit-message 와 **같은 Slack App** 을 쓴다. [api.slack.com/apps](https://api.slack.com/apps) → 해당 앱 → OAuth & Permissions → **User Token Scopes** 에 `files:write` 추가 (업로드·삭제 모두 이 스코프 하나면 된다)
3. Reinstall to Workspace 후 **User OAuth Token** (`xoxp-` 로 시작, `xoxb-` 아님) 을 `.env` 의 `SLACK_USER_TOKEN` 에 붙여넣기
4. 토큰은 이 Slack 스킬들이 공유하는 `~/.config/slack-user-token/.env` 에 두면 한 번만 붙여넣어도 된다 (스크립트가 이 경로를 먼저 찾는다). 없으면 `~/.config/slack-files/.env` 또는 스킬 폴더의 `.env` 를 쓴다.
5. `chmod +x slack-files.sh`

`.env` 는 gitignore 된다 — 토큰은 로컬에만 두고 레포(PUBLIC)에 커밋하지 않는다.

---
name: slack-channel-admin
description: Slack 채널을 생성(conversations.create)·보관(archive)·이름변경(rename)·토픽/목적 설정(setTopic/setPurpose)·초대(invite)·추방(kick)·읽음처리(mark)한다. claude_ai Slack MCP 도구셋엔 채널 생성/관리가 없어 xoxp user 토큰으로 Slack Web API 를 직접 호출한다.
argument-hint: "<채널> 보관해줘 | <채널> 만들어줘 | <유저>를 <채널>에서 내보내줘 | <채널> 토픽 ...로 바꿔줘"
allowed-tools: Bash, mcp__claude_ai_Slack__slack_search_channels, mcp__claude_ai_Slack__slack_search_users, mcp__claude_ai_Slack__slack_list_channel_members, mcp__claude_ai_Slack__slack_search_public, mcp__claude_ai_Slack__slack_search_public_and_private
---

# Slack Channel Admin

Slack 채널을 만들고 관리한다 (생성/보관/이름변경/토픽·목적 설정/멤버 초대·추방/읽음처리). `mcp__claude_ai_Slack__*` 도구셋에는 채널을 만들거나 관리하는 도구가 없어서(멤버 조회 `slack_list_channel_members` 만 있음), xoxp(user) 토큰으로 Slack Web API 의 `conversations.*` 를 직접 호출하는 이 스킬이 필요하다.

**⚠️ 이 스킬의 모든 서브커맨드는 다른 사람에게도 보이는 공유 워크스페이스 상태를 변경한다.** 채널 생성은 워크스페이스 전원에게 새 채널로 노출되고, 보관/이름변경은 모두에게 즉시 반영되며, 초대/추방은 대상 사용자의 접근 권한을 바꾼다. `archive`(보관)와 `kick`(추방)은 특히 되돌리기 어렵다 — 보관된 채널은 관리자가 되살릴 수 있지만 진행 중이던 대화·연동이 끊기고, 추방된 멤버는 재초대 전까지 그 채널의 기록에 접근할 수 없다.

## 1. channel_id / user_id 특정

- **채널**: `mcp__claude_ai_Slack__slack_search_channels` 로 채널명을 검색해 `channel_id`(`C...`/`G...`) 를 얻는다. 채널 링크를 주면 `https://<workspace>.slack.com/archives/<CHANNEL_ID>/...` 에서 `<CHANNEL_ID>` 를 파싱한다.
- **유저**: `mcp__claude_ai_Slack__slack_search_users` 로 이름/핸들을 검색해 `user_id`(`U...`) 를 얻는다. `invite`/`kick` 대상은 반드시 `U...` 형식의 user id 여야 한다 (표시 이름·핸들 아님).
- **멤버 확인**: `kick` 전에는 `mcp__claude_ai_Slack__slack_list_channel_members` 로 대상이 실제 그 채널 멤버인지 확인한다.
- 후보가 여러 개면 사용자에게 이름·용도를 보여주고 어떤 것인지 확인받는다.
- `create` 는 새로 만드는 것이라 사전 조회가 필요 없다 — 채널명만 필요하다 (소문자·숫자·하이픈·언더스코어, 공백 불가, 최대 80자).

## 2. 실행 전 확인 (필수)

**모든 서브커맨드는 예외 없이** 호출 전에 아래를 사용자에게 명시하고 명시적 승인을 받는다. `mark-read` 도 예외 아님.

- **무엇을**: 어떤 채널(이름 + `channel_id`)에 어떤 작업을 하는지
- **create**: 새 채널명, public/private 여부
- **rename**: 기존 이름 → 새 이름
- **set-topic / set-purpose**: 설정할 전체 문구
- **invite / kick**: 대상 사용자(표시 이름 + `user_id`) 를 반드시 함께 — 누구를 초대/추방하는지 오해 없게
- **archive / kick**: 되돌리기 어렵다는 점을 한 줄 경고로 덧붙인다

사용자가 명시적으로 승인하기 전에는 어떤 서브커맨드도 실행하지 않는다.

## 3. 실행

```bash
"${CLAUDE_SKILL_DIR}/slack-channel-admin.sh" create <name> [private]
"${CLAUDE_SKILL_DIR}/slack-channel-admin.sh" archive <channel_id>
"${CLAUDE_SKILL_DIR}/slack-channel-admin.sh" rename <channel_id> <new_name>
"${CLAUDE_SKILL_DIR}/slack-channel-admin.sh" set-topic <channel_id> "<토픽>"
"${CLAUDE_SKILL_DIR}/slack-channel-admin.sh" set-purpose <channel_id> "<목적>"
"${CLAUDE_SKILL_DIR}/slack-channel-admin.sh" invite <channel_id> <user_id[,user_id2,...]>
"${CLAUDE_SKILL_DIR}/slack-channel-admin.sh" kick <channel_id> <user_id>
"${CLAUDE_SKILL_DIR}/slack-channel-admin.sh" mark-read <channel_id> <ts>
```

- `create` 는 세 번째 인자로 리터럴 문자열 `private` 을 주면 비공개 채널로, 안 주면 공개 채널로 만든다.
- `invite` 의 유저 목록은 쉼표로 구분한 `U...` id 들이다 (최대 100명).

## 4. 응답 해석

응답 JSON 의 `ok` 필드를 확인한다. `false` 면 `error` 값을 그대로 사용자에게 보고한다. 자주 보는 값:

- `name_taken` — 같은 이름 채널이 이미 있음 (create/rename)
- `invalid_name` / `invalid_name_specials` / `invalid_name_maxlength` — 채널명 규칙 위반
- `already_archived` — 이미 보관된 채널
- `not_in_channel` / `user_not_in_channel` — 봇/대상이 채널 멤버 아님
- `cant_kick_self` / `cant_kick_from_general` — 자기 자신·#general 에서는 추방 불가
- `channel_not_found`, `user_not_found`
- `not_authed`, `missing_scope` — 토큰/스코프 문제 (셋업 참고)
- `restricted_action` — 워크스페이스 정책상 해당 작업이 관리자에게만 허용됨

`create` 성공 시 응답의 `.channel.id` 가 새 `channel_id` 다.

## 셋업

1. `.env.example` 을 `.env` 로 복사
2. 이미 `slack-edit-message` 등 다른 Slack 스킬을 셋업했다면 **같은 Slack App / 같은 토큰** 을 그대로 쓴다. 공유 토큰 경로 `~/.config/slack-user-token/.env` 에 `SLACK_USER_TOKEN` 이 이미 있으면 이 스킬도 자동으로 그 파일을 먼저 찾는다 (별도 `.env` 불필요).
3. 처음이라면 [api.slack.com/apps](https://api.slack.com/apps) → Create New App → From scratch
4. OAuth & Permissions → **User Token Scopes** 에 아래 스코프를 추가한다 (메서드마다 요구 스코프가 다르니 전부 넣어야 8개 서브커맨드가 모두 동작한다):
   - **공개 채널**: `channels:write`, `channels:write.topic`, `channels:write.invites`
   - **비공개 채널**: `groups:write`, `groups:write.topic`, `groups:write.invites`
   - (DM/멀티DM 대상까지 다룰 일이 있으면 `im:write`, `im:write.topic`, `mpim:write`, `mpim:write.topic` 도 — 일반적인 채널 관리엔 불필요)
5. Install(또는 Reinstall) to Workspace → **User OAuth Token** (`xoxp-` 로 시작, `xoxb-` 아님) 복사해 `.env` 의 `SLACK_USER_TOKEN` 에 붙여넣기. 스코프를 추가한 뒤에는 반드시 Reinstall 해야 반영된다.
6. `chmod +x slack-channel-admin.sh`
7. 토큰 확인: `"${CLAUDE_SKILL_DIR}/slack-channel-admin.sh" whoami` → `ok:true` + 본인 user id 가 나오면 정상

`.env` 는 gitignore 된다 — 토큰은 로컬에만 두고 레포(PUBLIC)에 커밋하지 않는다.

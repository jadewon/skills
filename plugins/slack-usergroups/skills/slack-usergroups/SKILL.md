---
name: slack-usergroups
description: Slack 유저그룹(@-멘션 가능한 커스텀 그룹)을 생성(usergroups.create)/수정(usergroups.update)하고 멤버십을 교체(usergroups.users.update)한다. claude_ai Slack MCP 도구셋엔 usergroups.* 가 없어 xoxp user 토큰으로 Slack Web API 를 직접 호출한다.
argument-hint: "'<이름>' 유저그룹 만들어줘 | <그룹id> 멤버를 A·B 로 바꿔줘"
allowed-tools: Bash, mcp__claude_ai_Slack__slack_search_users
---

# Slack User Groups

Slack 유저그룹(팀 전체가 `@디자인`, `@온콜` 처럼 한 번에 멘션할 수 있는 커스텀 그룹)을 만들고, 이름/핸들을 바꾸고, 소속 멤버를 관리한다. `mcp__claude_ai_Slack__*` 도구셋에는 `usergroups.*` 가 없어서 xoxp(user) 토큰으로 Slack Web API 를 직접 호출하는 이 스킬이 필요하다.

**이 배치에서 가장 관리자 성격이 강하고 우선순위가 낮은 스킬이다.** 유저그룹 관리는 보통 팀 규모 워크스페이스에서만 의미가 있고, 개인 워크스페이스에서는 잘 안 쓴다. 게다가 워크스페이스 설정에서 "유저그룹 관리"를 관리자에게만 열어둔 경우가 많아 — 그때는 `missing_scope` 가 아니라 `permission_denied` 가 나온다. 또한 유저그룹 기능 자체가 **유료 Standard 이상 플랜에서만** 제공된다. 셋업했는데도 권한 벽에 막힐 수 있음을 미리 알아둘 것.

## 1. 대상/멤버 특정

- 유저그룹 id (`S...` 로 시작) 는 사용자가 주거나, `create` 응답의 `.usergroup.id` 에서 얻는다.
- 멤버로 넣을 사용자 id (`U...`) 는 `mcp__claude_ai_Slack__slack_search_users` 로 이름 → id 를 해석한다.
- `set-users` 는 멤버십을 **통째로 교체**하므로(아래 참고), 넣을 사람 전원의 id 를 먼저 확정한 뒤 한 번에 넘긴다.

## 2. 실행 전 확인 (필수)

`create`/`update`/`set-users` 는 모두 **워크스페이스 전체에 보이는 상태**(멘션 가능한 그룹과 그 멤버 목록)를 바꾼다. 실행 전 아래를 사용자에게 보여주고 확인받는다:

- `create`: 만들 그룹 이름과 handle
- `update`: 대상 그룹 id, 바꿀 이름/handle (바꾸지 않는 필드는 그대로 둔다)
- `set-users`: **⚠️ 멤버십을 REPLACE 한다 — 기존 멤버에 추가하는 게 아니라, 넘긴 목록이 그대로 전체 멤버가 된다.** 빠뜨린 사람은 그룹에서 빠진다. 반드시 "최종 전체 멤버 명단"을 사용자에게 확인받고 나서 호출한다.

## 3. 실행

```bash
# 생성 (handle 은 생략 가능)
"${CLAUDE_SKILL_DIR}/slack-usergroups.sh" create "디자인 팀" design

# 이름/핸들 수정 (넘긴 필드만 갱신)
"${CLAUDE_SKILL_DIR}/slack-usergroups.sh" update S0123ABCD "프로덕트 디자인"

# 멤버십 통째 교체 (쉼표구분 U... id — REPLACE 임에 주의)
"${CLAUDE_SKILL_DIR}/slack-usergroups.sh" set-users S0123ABCD U111,U222,U333
```

응답 JSON 의 `ok` 필드를 확인한다. `false` 면 `error` 값을 그대로 사용자에게 보고한다. 자주 보는 값:

- `permission_denied` — 이 사용자가 유저그룹을 만들/바꿀 권한이 없음 (워크스페이스가 관리자에게만 허용). 관리자 권한 계정의 user 토큰이 필요하다.
- `missing_scope` — 토큰에 `usergroups:write` 스코프가 없음 (셋업 참고).
- `paid_teams_only` / feature 미제공 — 유저그룹은 Standard 이상 플랜 전용.
- `subteam_max_users_exceeded`, `invalid_users`, `no_users_provided` — `set-users` 인자 문제. (참고: 멤버를 전부 빼는 건 불가 — 그럴 땐 `usergroups.disable` 를 써야 하며 이 스킬 범위 밖이다.)

## 셋업

1. `.env.example` 을 `.env` 로 복사
2. `slack-edit-message` 와 **같은 Slack App** 을 그대로 쓴다. [api.slack.com/apps](https://api.slack.com/apps) → 해당 앱 → OAuth & Permissions → **User Token Scopes** 에 `usergroups:write` 추가 → Reinstall to Workspace
3. 발급된 **User OAuth Token** (`xoxp-` 로 시작, `xoxb-` 아님) 을 `.env` 의 `SLACK_USER_TOKEN` 에 넣는다.
   - 이 배치의 다른 Slack 스킬과 토큰을 공유한다: `~/.config/slack-user-token/.env` 에 한 번만 넣어두면 모든 Slack 스킬이 같이 읽는다.
4. `chmod +x slack-usergroups.sh`

`.env` 는 gitignore 된다 — 토큰은 로컬에만 두고 레포(PUBLIC)에 커밋하지 않는다.

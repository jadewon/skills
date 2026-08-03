# slack-scheduled-message

미래의 나에게 보낼 Slack 메시지를 채널로 예약한다. 메시지에는 `cd <현재경로> && claude --resume <세션>` 명령이 포함되어, 메시지가 도착했을 때 한 번에 **지금 이 대화**로 복귀할 수 있다.

> ⚠️ **먼저 읽기:** 메시지는 내가 아니라 **봇 명의로** 발송된다. Slack 은 자기가 보낸 메시지에 대해 알림을 주지 않아서, 본인 명의로 보낸 알림은 소리 없이 도착한다. 그래서 봇 발신이 이 스킬의 핵심이다. → [주의사항](#주의사항)

> [English](./README.md)

## Why

지금 Claude Code 와 대화 중인데, 다음 액션은 며칠/몇 시간 뒤에 있어야 하는 상황 (회의 끝, 배포 창구, 정기 리뷰 등). 머릿속 TODO 로 남기지 말고, 그 시점의 자신에게 *이 세션* 의 resume 명령을 박아서 슬랙으로 던져두자.

## 사용법

```
/slack-scheduled-message 5/11 09:32 회의 끝나고 컨텍스트 정리 이어가기
/slack-scheduled-message 내일 21:00 다음 단계 PR 분기 as plugin-marketplace
/slack-scheduled-message 2026-05-15 14:00 데모 직전 마지막 점검
```

자연어도 OK:

```
5월 11일 월요일 9시 32분에 슬랙으로 알려줘 — 컨텍스트 이어가는 거 잊지 말라고 (이름: skill-design)
```

## 전송되는 메시지 형태

````
:alarm_clock: <메시지>

```
cd "<현재 경로>" && claude --resume "<custom name ?? 현재 세션 ID>"
```
````

예약 메시지는 항상 `:alarm_clock:` 으로 시작한다 — 채널에 흘러드는 다른 봇 알림과 한눈에 구분하기 위한 표식이다.
코드 펜스에는 언어 태그를 붙이지 않는다. Slack 은 펜스 하이라이팅을 지원하지 않아 `bash` 가 스니펫 첫 줄로 그대로
찍히고, 명령을 복사할 때 같이 딸려온다.

**Resume 타겟 결정 순서:** `user_custom_name ?? session_name ?? $CLAUDE_CODE_SESSION_ID`
1. 입력에 `as <name>` / `이름: <name>` 으로 명시한 게 있으면 그게 우선.
2. 없으면 Claude Code 의 `/name` 으로 설정한 현재 세션 이름 (`~/.claude/sessions/<pid>.json` 의 `name` 필드).
3. 그것도 없으면 UUID.

## 동작

- **타임존:** Asia/Seoul (KST)
- **발신자:** 내가 아니라 봇 (`as: "bot"`) — [주의사항](#주의사항) 참고
- **수신지:** 채널. 첫 사용 시 한 번 묻고 `~/.config/slack-scheduled-message/channel_id` 에 캐시. 바꾸려면 캐시 파일 `rm`.
- **Resume 타겟:** `user_custom_name ?? session_name ?? $CLAUDE_CODE_SESSION_ID` (앞쪽이 우선)
- **제약:** Slack 스케줄링 규칙상 최소 2분 뒤, 최대 120일 이내

## 주의사항

**Slack 은 자기가 보낸 메시지에 대해 알림을 주지 않는다** — 본인 DM 이든 아니든, 어느 채널이든 push·소리·배지가 전부 없다. 그래서 user 토큰으로 건 예약은 채널에 조용히 도착만 하고 본인은 끝까지 모른다. 본인 DM 만의 특성이 아니고, 클라이언트 설정으로도 못 바꾼다.

그래서 이 스킬의 발송·조회·취소는 전부 봇 토큰으로 서명한다 (`mcp__slack__slack_api` 의 `as: "bot"`). 발신자가 남이 되므로 알림이 정상적으로 뜬다. 여기서 두 가지가 따라온다.

- 수신지는 **봇이 들어가 있는 채널**이어야 한다. 본인 DM 은 애초에 불가능하다 — 봇이 접근할 수 없고, 본인 발신이면 어차피 알림도 안 온다. 자기만 있는 private 채널 (예: `#jade-notes`) 을 만들고 봇을 초대해서 쓴다.
- 예약된 메시지의 **소유자는 봇**이다. 내 `chat.scheduledMessages.list` 에는 안 보이고, 취소도 봇 토큰으로만 된다.

## 취소 / 조회

둘 다 `mcp__slack__slack_api` 에 **`as: "bot"` 을 붙여서** 처리한다. 빠뜨리면 예약이 보이지도, 취소되지도 않는다.

- 조회 — `method` `chat.scheduledMessages.list`, `as` `bot`, `params.channel` (생략하면 전체)
- 취소 — `method` `chat.deleteScheduledMessage`, `as` `bot`, `params` `{channel, scheduled_message_id}`

API 로 *수정*은 여전히 불가 — 취소 후 재예약.

## 셋업

`~/.config/slack-user-token/.env` 에 `SLACK_USER_TOKEN` (xoxp) 과 `SLACK_BOT_TOKEN` (xoxb, `chat:write`) 둘 다 있어야 한다. [slack-mcp](https://github.com/jadewon/mcps/tree/main/slack-mcp) 서버가 이 파일을 읽는다. 그 봇을 수신 채널에 초대해둘 것.

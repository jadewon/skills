# slack-scheduled-message

미래의 나에게 보낼 Slack 메시지를 예약한다 (기본: 본인 DM, 권장: private 채널). 메시지에는 `cd <현재경로> && claude --resume <세션>` 명령이 포함되어, 메시지가 도착했을 때 한 번에 **지금 이 대화**로 복귀할 수 있다.

> ⚠️ **먼저 읽기:** Slack 은 본인 DM 에 푸시 알림을 안 보낸다. 첫 사용 시 스킬이 `AskUserQuestion` 으로 어디로 보낼지 묻는다. 푸시가 정말로 와야 한다면 private 채널을 골라라. → [주의사항](#주의사항)

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

```
<메시지>

```bash
cd "<현재 경로>" && claude --resume "<custom name ?? 현재 세션 ID>"
```
```

**Resume 타겟 결정 순서:** `user_custom_name ?? session_name ?? $CLAUDE_CODE_SESSION_ID`
1. 입력에 `as <name>` / `이름: <name>` 으로 명시한 게 있으면 그게 우선.
2. 없으면 Claude Code 의 `/name` 으로 설정한 현재 세션 이름 (`~/.claude/sessions/<pid>.json` 의 `name` 필드).
3. 그것도 없으면 UUID.

## 동작

- **타임존:** Asia/Seoul (KST)
- **수신지:** 첫 사용 시 `AskUserQuestion` 으로 한 번 묻는다 — `내 DM` (기본, 푸시 안 옴) 또는 `특정 채널/그룹` (알림 받으려면 권장). `~/.config/slack-scheduled-message/channel_id` 에 캐시. 바꾸려면 캐시 파일 `rm`.
- **Resume 타겟:** `user_custom_name ?? session_name ?? $CLAUDE_CODE_SESSION_ID` (앞쪽이 우선)
- **제약:** Slack 스케줄링 규칙상 최소 2분 뒤, 최대 120일 이내

## 주의사항

Slack 은 본인 DM 에 대해 발신자와 무관하게 push/소리/배지 알림을 억제한다 — Claude Slack 앱으로 보내도 우회되지 않으며, DM 채널 안의 unread 배지만 뜬다. 예약 시각에 확실한 push 가 필요하면, 자기만 들어 있는 private 채널 (예: `#jade-notes`) 로 예약하거나, 메시지에 본인 멘션 `<@U…>` 을 포함시킨다 (일부 워크스페이스에서는 알림이 살아나지만, 워크스페이스 설정에 따라 다름).

## 취소 / 조회

```bash
slack-scheduled-message.sh list-scheduled <channel_id>
slack-scheduled-message.sh cancel-scheduled <channel_id> <scheduled_message_id>
```

`SLACK_USER_TOKEN` 필요 (`.env.example` 참고) — 예약 자체는 MCP 도구를 쓰므로 토큰이 필요 없지만, list/cancel 은 MCP 도구셋에 없는 `chat.scheduledMessages.list`/`chat.deleteScheduledMessage` 를 직접 호출한다. API 로 *수정*은 여전히 불가 — 취소 후 재예약.

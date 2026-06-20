---
name: fearandgreed
description: 매일 아침 CNN Fear & Greed Index 를 조회해 Slack 채널에 게시한다. 점수·등급·게이지 + 전일/주/월/년 비교. 결정론 스크립트라 그대로 실행만 한다.
allowed-tools: Bash
---

# Fear & Greed Daily

CNN Fear & Greed Index 를 조회해 Slack 에 게시한다. 메시지 작성·포맷·전송까지 스크립트가 전부 처리하는 결정론 작업 — 아래 한 줄만 실행하면 된다.

## 절대 규칙

- 코드베이스 탐색/구조 파악을 하지 마라. 아래 실행만 하면 끝이다.
- 메시지를 직접 작성하거나 가공하지 마라. 스크립트 출력이 그대로 게시된다.

## 실행

```bash
"${CLAUDE_SKILL_DIR}/fearandgreed.sh"
```

스크립트가 CNN API 조회 → 포맷(점수/등급/게이지/비교표) → Slack webhook 게시까지 처리한다. 스크립트가 0 으로 종료하면 게시 성공. 비-0 종료면 stderr 의 에러를 보고하고 종료.

설정값(webhook)은 `.env` 의 `SLACK_WEBHOOK_URL` 에서 로드한다. `.env.example` 참고.

## 셋업

1. `.env.example` 을 `.env` 로 복사
2. `SLACK_WEBHOOK_URL` 채움 (Slack incoming webhook, 채널 고정형)
3. `chmod +x fearandgreed.sh`

`.env` 는 gitignore 된다 — webhook 은 서버/로컬에만 두고 레포(PUBLIC)에 커밋하지 않는다.

## 스케줄

always-on 서버 cron 권장 (Mac 로컬은 꺼지면 miss):

```cron
0 9 * * 1-5 cd /path/to/skills/fearandgreed && claude --print /fearandgreed
```

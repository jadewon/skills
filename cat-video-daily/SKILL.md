---
name: cat-video-daily
description: 매일 오후 Mastodon 고양이 해시태그에서 좋아요가 가장 많은 영상을 골라 Slack 채널에 업로드한다. 결정론 스크립트라 그대로 실행만 한다.
allowed-tools: Bash
---

# Cat Video Daily

선택·다운로드·업로드는 결정론 스크립트가 하고, 글 내용을 한국어 한 줄 제목으로 바꾸는 것만 스크립트 안에서 `claude -p --model haiku` 로 한다(실패 시 제목 없이 게시). 보통은 cron 에서 `cat-video-daily.sh` 를 직접 실행한다. 이 스킬은 수동 실행용이다.

## 절대 규칙

- 코드베이스 탐색/구조 파악을 하지 마라. 아래 실행만 하면 끝이다.
- 메시지를 직접 작성하거나 가공하지 마라.

## 실행

```bash
"${CLAUDE_SKILL_DIR}/cat-video-daily.sh"
```

공휴일 체크 → Mastodon 해시태그(catsofmastodon, caturday, cats) 최근 7일 영상 수집 → 좋아요 순 정렬(이미 올린 글·CW 글 제외) → 내려받기 → Haiku 한국어 제목 → Slack 업로드까지 스크립트가 처리한다. `ok` 또는 `공휴일 스킵` 이면 정상, 비-0 종료면 stderr 에러를 보고한다. `--dry-run` 은 전송 없이 고르고 내려받기까지만 한다.

## 셋업

- Slack 설정은 `~/.config/cat-daily/.env` (cat-photo-daily 와 공유, `SLACK_BOT_TOKEN` / `SLACK_CHANNEL`). 봇 토큰에 `files:write` 필요. `claude` 경로는 `CLAUDE_BIN` (기본 `~/.local/bin/claude`).
- 게시 기록: `~/.local/state/cat-video-daily/posted.txt` — 같은 영상을 다시 올리지 않는다.
- cron 예시: `0 16 * * 1-5 <repo>/plugins/cat-video-daily/skills/cat-video-daily/cat-video-daily.sh > /tmp/cat-video-daily.log 2>&1`

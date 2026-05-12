# 개인편의성을 위해 만들어서 사용하는 스킬들

Claude Code custom skills.

> [English](./README.md)

## Setup

### Option 1: Plugin Marketplace (권장)

레포 clone 없이 설치:

```bash
# marketplace 등록 (한번만)
/plugin marketplace add jadewon/skills

# 개별 플러그인 설치
/plugin install remind@jadewon-skills
```

### Option 2: Symlink (기존 방식)

```bash
# 이 레포를 클론한 뒤, 사용할 스킬을 심볼릭 링크로 연결
ln -s /path/to/this-repo/remind ~/.claude/skills/remind
# 또는 plugin 구조에서
ln -s /path/to/this-repo/plugins/remind/skills/remind ~/.claude/skills/remind
```

## Skills

| Skill | Description | Usage |
|-------|-------------|-------|
| [remind](./remind) | macOS 알림 타이머 | `/remind 5m 회의 시작` 또는 `5분 뒤 회의 시작 알림 설정해줘` |
| [slack-scheduled-message](./slack-scheduled-message) | `claude --resume <세션>` 명령이 담긴 Slack 메시지 예약 (기본 본인 DM, private 채널로 설정 가능) | `/slack-scheduled-message 5/11 09:32 ...` 또는 자연어 |
| [weather-daily](./weather-daily) | 한국 기상청/에어코리아 API 로 오늘 날씨를 조회해 친근한 비서 톤으로 Slack 채널에 발송 (온도·습도·UV 한 줄 요약 + 옷차림·우산·미세먼지 등 행동 조언) | `/weather-daily` (보통 always-on 서버 cron 08:00 KST 에 연결) |

## Structure

> 루트의 `remind/`는 기존 symlink 방식 호환용이고, `plugins/` 하위는 plugin marketplace 설치용입니다. 스킬 파일이 두 벌로 존재하는 이유는 두 설치 방식을 모두 지원하기 위함입니다.

```
skills/
├── .claude-plugin/
│   └── marketplace.json        # Plugin marketplace 정의
├── plugins/                    # Plugin 구조 (marketplace 설치용)
│   ├── remind/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/remind/
│   ├── slack-scheduled-message/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/slack-scheduled-message/
│   └── weather-daily/
│       ├── .claude-plugin/plugin.json
│       └── skills/weather-daily/
├── remind/                     # 기존 구조 (symlink 호환)
├── slack-scheduled-message/
└── weather-daily/
```

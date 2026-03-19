# 개인편의성을 위해 만들어서 사용하는 스킬들

Claude Code custom skills.

## Setup

```bash
# 이 레포를 클론한 뒤, 사용할 스킬을 심볼릭 링크로 연결
ln -s /path/to/this-repo/<skill-name> ~/.claude/skills/<skill-name>
```

## Skills

| Skill | Description | Usage |
|-------|-------------|-------|
| [remind](./remind) | macOS 알림 타이머 | `/remind 5m 회의 시작` 또는 `5분 뒤 회의 시작 알림 설정해줘` |

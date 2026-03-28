# 개인편의성을 위해 만들어서 사용하는 스킬들

Claude Code custom skills.

## Setup

### Option 1: Plugin Marketplace (권장)

레포 clone 없이 설치:

```bash
# marketplace 등록 (한번만)
/plugin marketplace add jadewon/skills

# 개별 플러그인 설치
/plugin install remind@jadewon-skills
/plugin install product-docs@jadewon-skills
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
| [product-docs](./product-docs) | 중앙 제품 문서 레포에 문서 생성/수정 + 자동 PR | `/product-docs feature 로그인 기능` 또는 `API 문서 추가해줘` |

## Structure

> 루트의 `remind/`, `product-docs/`는 기존 symlink 방식 호환용이고, `plugins/` 하위는 plugin marketplace 설치용입니다. 스킬 파일이 두 벌로 존재하는 이유는 두 설치 방식을 모두 지원하기 위함입니다.

```
skills/
├── .claude-plugin/
│   └── marketplace.json        # Plugin marketplace 정의
├── plugins/                    # Plugin 구조 (marketplace 설치용)
│   ├── remind/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json
│   │   └── skills/remind/
│   └── product-docs/
│       ├── .claude-plugin/
│       │   └── plugin.json
│       └── skills/product-docs/
├── remind/                     # 기존 구조 (symlink 호환)
└── product-docs/               # 기존 구조 (symlink 호환)
```

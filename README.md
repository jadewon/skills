# Custom Skills for Claude Code

Personal productivity skills for Claude Code.

> [한국어](./README.ko.md)

## Setup

### Option 1: Plugin Marketplace (recommended)

No clone required:

```bash
# Register marketplace (once)
/plugin marketplace add jadewon/skills

# Install individual plugins
/plugin install remind@jadewon-skills
```

### Option 2: Symlink

```bash
# Clone this repo, then symlink the skill you want
ln -s /path/to/this-repo/remind ~/.claude/skills/remind
# Or from the plugin structure
ln -s /path/to/this-repo/plugins/remind/skills/remind ~/.claude/skills/remind
```

## Skills

| Skill | Description | Usage |
|-------|-------------|-------|
| [remind](./remind) | macOS notification timer | `/remind 5m meeting` or natural language |
| [slack-scheduled-message](./slack-scheduled-message) | Schedule a future Slack message (default self-DM, configurable to private channel) with a `claude --resume <session>` command | `/slack-scheduled-message 5/11 09:32 ...` or natural language |
| [weather-daily](./weather-daily) | Daily weather brief for Korea — KMA forecast + air quality + UV, posted to Slack as a one-line summary (temp / humidity / UV) plus actionable advice (outfit / umbrella / mask) | `/weather-daily` (typically wired to a cron at 08:00 KST on an always-on host) |

## Structure

> Root-level `remind/` is for backward-compatible symlink installs. `plugins/` contains the same skill wrapped for plugin marketplace installs. Skill files exist in both locations to support both setup methods.

```
skills/
├── .claude-plugin/
│   └── marketplace.json        # Plugin marketplace definition
├── plugins/                    # Plugin structure (for marketplace install)
│   ├── remind/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/remind/
│   ├── slack-scheduled-message/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/slack-scheduled-message/
│   └── weather-daily/
│       ├── .claude-plugin/plugin.json
│       └── skills/weather-daily/
├── remind/                     # Legacy structure (symlink compatible)
├── slack-scheduled-message/
└── weather-daily/
```
